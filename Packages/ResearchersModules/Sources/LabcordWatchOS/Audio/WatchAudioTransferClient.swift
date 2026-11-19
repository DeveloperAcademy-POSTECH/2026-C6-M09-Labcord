import Foundation
import LabcordShared
import WatchConnectivity

public enum WatchAudioDeliveryEvent: Sendable {
    case receipt(WatchAudioReceipt)
    case failed(WatchAudioHeader, WatchExperimentError)
}

@MainActor
public final class WatchAudioTransferClient {
    public typealias Exchange = @Sendable (WatchAudioMessage) async throws -> WatchAudioReceipt
    private let archive: WatchAudioArchive
    private let exchange: Exchange
    private var recovery: Task<Void, Never>?
    private var verification: Task<Void, Never>?
    private var isRecovering = false
    public private(set) var lastError: WatchAudioError?
    public private(set) var lastDeliveryError: WatchExperimentError?
    public private(set) var damagedRecordingIDs: [UUID] = []
    private var observers: [UUID: AsyncStream<WatchAudioDeliveryEvent>.Continuation] = [:]
    private var verifiedObservers: [UUID: WeakWatchAudioVerifiedSaveObservation] = [:]
    private var lastReceipts: [UUID: WatchAudioReceipt] = [:]
    private let confirmationKey = "Labcord.WatchAudio.pendingConfirmations"
    private var legacyConfirmations: [UUID: WatchAudioHeader] = [:]
    private let cancellationKey = "Labcord.WatchAudio.pendingCancellations"
    private var deferredCancellations: Set<UUID> = []
    public func isCancellationPending(_ header: WatchAudioHeader) -> Bool {
        isCancellationPending(recordingID: header.recordingID)
    }

    public func isCancellationPending(recordingID: UUID) -> Bool {
        (UserDefaults.standard.stringArray(forKey: cancellationKey) ?? [])
            .contains(recordingID.uuidString)
    }

    public func prepareCancellation(_ header: WatchAudioHeader) {
        if let receipt = lastReceipts[header.recordingID],
           receipt.isSavedAcknowledgement || receipt.isCancelled { return }
        deferredCancellations.insert(header.recordingID)
        var ids = Set(UserDefaults.standard.stringArray(forKey: cancellationKey) ?? [])
        ids.insert(header.recordingID.uuidString)
        UserDefaults.standard.set(Array(ids), forKey: cancellationKey)
    }

    public func releaseCancellation(_ header: WatchAudioHeader) {
        deferredCancellations.remove(header.recordingID)
    }

    private func clearCancellation(_ header: WatchAudioHeader) {
        var ids = Set(UserDefaults.standard.stringArray(forKey: cancellationKey) ?? [])
        guard ids.remove(header.recordingID.uuidString) != nil else { return }
        UserDefaults.standard.set(Array(ids), forKey: cancellationKey)
    }

    private func checkCancellation(_ header: WatchAudioHeader) throws {
        if isCancellationPending(header) { throw CancellationError() }
    }

    public init(archive: WatchAudioArchive, exchange: @escaping Exchange) {
        self.archive = archive
        self.exchange = exchange
        let pending = UserDefaults.standard.data(forKey: confirmationKey)
            .flatMap { try? JSONDecoder().decode([WatchAudioHeader].self, from: $0) } ?? []
        legacyConfirmations = Dictionary(
            pending.map { ($0.recordingID, $0) }
        ) { first, _ in first }
    }

    deinit {
        recovery?.cancel()
        verification?.cancel()
    }

    public func hasPendingConfirmation(_ header: WatchAudioHeader) async -> Bool {
        if let receipt = lastReceipts[header.recordingID],
           receipt.isSavedAcknowledgement || receipt.isCancelled { return false }
        if legacyConfirmations[header.recordingID] == header { return true }
        return await archive.isConfirmed(header)
    }

    public func requestConfirmation(_ header: WatchAudioHeader) async throws {
        try checkCancellation(header)
        if lastReceipts[header.recordingID]?.isSavedAcknowledgement == true { return }
        try await archive.confirm(header)
    }

    private func persistConfirmations() {
        let headers = Array(legacyConfirmations.values)
        UserDefaults.standard.set(try? JSONEncoder().encode(headers), forKey: confirmationKey)
    }

    public func events() -> AsyncStream<WatchAudioDeliveryEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<WatchAudioDeliveryEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.observers.removeValue(forKey: id) }
        }
        return stream
    }

    public func observeVerifiedSaves() -> WatchAudioVerifiedSaveObservation {
        let id = UUID()
        let observation = WatchAudioVerifiedSaveObservation { [weak self] in
            self?.verifiedObservers.removeValue(forKey: id)
        }
        verifiedObservers[id] = WeakWatchAudioVerifiedSaveObservation(observation)
        return observation
    }

    private func publishVerified(_ receipt: WatchAudioReceipt) {
        for (id, observer) in Array(verifiedObservers) {
            guard let observation = observer.value else {
                verifiedObservers.removeValue(forKey: id)
                continue
            }
            observation.publish(receipt)
        }
    }

    public func startRecovery() {
        guard recovery == nil else { return }
        recovery = Task { [weak self] in
            while !Task.isCancelled {
                await self?.recover()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    public func stopRecovery() {
        recovery?.cancel()
        recovery = nil
        verification?.cancel()
    }

    public func recover() async {
        guard !isRecovering else { return }
        isRecovering = true
        defer { isRecovering = false }
        do {
            let headers = try await scanArchiveHeaders().sorted { $0.startedAt > $1.startedAt }
            for header in headers {
                try Task.checkCancellation()
                do {
                    try await recover(header)
                } catch is CancellationError {
                    try Task.checkCancellation()
                } catch {
                    lastError = (error as? WatchAudioError) ?? .interrupted
                    let deliveryError = (error as? WatchExperimentError) ?? .resultUnknown
                    lastDeliveryError = deliveryError
                    observers.values.forEach { $0.yield(.failed(header, deliveryError)) }
                    do { try await enqueueBackground(header) } catch {
                        lastError = (error as? WatchAudioError) ?? .interrupted
                    }
                }
            }
        } catch is CancellationError {
            return
        } catch {
            lastError = (error as? WatchAudioError) ?? .interrupted
        }
    }

    private func scanArchiveHeaders() async throws -> [WatchAudioHeader] {
        let scan = try await archive.scanHeaders()
        damagedRecordingIDs = scan.damagedRecordingIDs
        if !damagedRecordingIDs.isEmpty { lastError = .invalidAudio }
        return scan.headers
    }
}

extension WatchAudioTransferClient {
    private func enqueueBackground(_ header: WatchAudioHeader) async throws {
        guard WatchConnectivityState(.default).canTransfer else { return }
        if isCancellationPending(header) {
            if !deferredCancellations.contains(header.recordingID) {
                enqueueBackgroundControl(.cancel(header))
            }
            return
        }
        let local = try await archive.statusEnsuringArchive(header)
        let remote = try await archive.remoteReceipt(header)
        guard local.savedRecordID == nil, !local.isCancelled,
              remote?.isSavedAcknowledgement != true,
              !isCancellationPending(header) else { return }
        if await hasPendingConfirmation(header), !isCancellationPending(header) {
            enqueueBackgroundControl(.confirm(header))
        }
        guard let manifest = local.manifest, !local.receivedSequences.isEmpty else { return }
        enqueueBackgroundProgress(manifest, remote: remote)
        let received = Set(remote?.receivedSequences ?? [])
        for sequence in local.receivedSequences where !received.contains(sequence) {
            let url = try await archive.retainedChunkURL(header, sequence: sequence)
            try checkCancellation(header)
            let outstanding = WCSession.default.outstandingFileTransfers
            guard outstanding.count < 2 else { return }
            guard !outstanding.contains(where: { $0.file.fileURL == url }) else { continue }
            WatchConnectivityDiagnostics.queueFile(
                url, metadata: ["labcordAudioChunk": true], on: .default
            )
        }
    }

    private func enqueueBackgroundProgress(
        _ manifest: WatchAudioManifest, remote: WatchAudioReceipt?
    ) {
        if remote?.manifest != manifest {
            enqueueBackgroundControl(.finish(manifest))
        } else if remote?.failure != nil {
            enqueueBackgroundControl(.status(manifest.header))
        }
    }

    private func enqueueBackgroundControl(_ message: WatchAudioMessage) {
        let key = "labcordAudioMessage"
        guard let data = try? JSONEncoder().encode(message),
              !WCSession.default.outstandingUserInfoTransfers.contains(where: {
                  ($0.userInfo[key] as? Data).flatMap {
                      try? JSONDecoder().decode(WatchAudioMessage.self, from: $0)
                  } == message
              }) else { return }
        WatchConnectivityDiagnostics.queueUserInfo([key: data], on: .default)
    }

    public func receive(_ receipt: WatchAudioReceipt) async throws {
        let header = receipt.header
        let terminal = receipt.isCancelled || receipt.isSavedAcknowledgement
        guard lastReceipts[header.recordingID] != receipt,
              receipt.savedRecordID == nil || receipt.isSavedAcknowledgement,
              !isCancellationPending(header) || terminal else { return }
        if !receipt.isCancelled,
           try await archive.statusIfPresent(header).isCancelled { return }
        guard try await archive.rememberRemoteReceipt(receipt) else { return }
        if receipt.isCancelled { _ = try await archive.cancel(header) }
        if terminal {
            clearCancellation(header)
            if legacyConfirmations.removeValue(forKey: header.recordingID) != nil {
                persistConfirmations()
            }
        }
        lastError = receipt.failure ?? (damagedRecordingIDs.isEmpty ? nil : .invalidAudio)
        publishReceipt(receipt)
    }

    private func publishReceipt(_ receipt: WatchAudioReceipt) {
        let id = receipt.header.recordingID
        if let previous = lastReceipts[id],
           previous == receipt || !receipt.canReplace(previous) { return }
        lastReceipts[id] = receipt
        observers.values.forEach { $0.yield(.receipt(receipt)) }
    }

    private func recover(_ header: WatchAudioHeader) async throws {
        let local = try await archive.statusEnsuringArchive(header)
        if let remote = try await archive.remoteReceipt(header),
           remote.isSavedAcknowledgement || remote.isCancelled {
            do {
                try await receive(remote)
                if !remote.isCancelled, local.savedRecordID == nil {
                    scheduleVerification(header)
                }
                if !remote.isCancelled, try await archive.needsSavedCleanup(header) {
                    scheduleVerification(header)
                }
                return
            } catch WatchAudioError.conflict {
                // A receipt from an older build may not have been checked against the PCM.
                _ = try await request(.status(header), for: header)
                return
            }
        }
        if isCancellationPending(header) {
            guard !deferredCancellations.contains(header.recordingID) else { return }
            _ = try await cancel(header)
            return
        }
        if local.savedRecordID != nil {
            if try await archive.needsSavedCleanup(header) { scheduleVerification(header) }
            return
        }
        guard !local.isCancelled, !local.receivedSequences.isEmpty else { return }
        try await recoverUnsaved(header, local: local)
    }

    private func recoverUnsaved(
        _ header: WatchAudioHeader, local: WatchAudioReceipt
    ) async throws {
        var remote = try await request(.status(header), for: header)
        guard !remote.isCancelled, remote.savedRecordID == nil else { return }
        for sequence in local.receivedSequences {
            guard !remote.receivedSequences.contains(sequence) else { continue }
            try Task.checkCancellation()
            try checkCancellation(header)
            let chunk = try await archive.chunk(header, sequence)
            try checkCancellation(header)
            remote = try await request(.chunk(chunk), for: header)
            guard !remote.isCancelled, remote.savedRecordID == nil else { return }
        }
        if let manifest = local.manifest, remote.manifest != manifest {
            try checkCancellation(header)
            remote = try await request(.finish(manifest), for: header)
        }
        if await hasPendingConfirmation(header), !remote.isCancelled, remote.savedRecordID == nil {
            _ = try await confirm(header)
        }
        lastDeliveryError = nil
    }

    private func request(
        _ message: WatchAudioMessage, for header: WatchAudioHeader
    ) async throws -> WatchAudioReceipt {
        let receipt = try await exchange(message)
        guard receipt.header == header else { throw WatchAudioError.conflict }
        if let error = receipt.failure, receipt.stateRevision == nil,
           receipt.manifest == nil, receipt.receivedSequences.isEmpty {
            throw error.watchExperimentError
        }
        try await receive(receipt)
        return receipt
    }

    private func scheduleVerification(_ header: WatchAudioHeader) {
        guard verification == nil else { return }
        verification = Task { [weak self] in
            guard let self else { return }
            defer { verification = nil }
            do {
                let receipt = try await verifySaved(header)
                publishVerified(receipt)
            } catch is CancellationError {
                return
            } catch {
                lastError = (error as? WatchAudioError) ?? .interrupted
            }
        }
    }
    public func verifySaved(_ header: WatchAudioHeader) async throws -> WatchAudioReceipt {
        var verified: WatchAudioReceipt?
        try await WatchAudioRecoveryRunner.refreshSaved(header, query: exchange) { receipt in
            try self.checkCancellation(header)
            try await self.archive.acknowledgeSavedAndCleanUp(receipt)
            if try await self.archive.remoteReceipt(header)?.isSavedAcknowledgement != true {
                try await self.receive(receipt)
            }
            verified = receipt
        }
        guard let verified else { throw WatchAudioError.incomplete }
        return verified
    }

    public func confirm(_ header: WatchAudioHeader) async throws -> WatchAudioReceipt {
        try checkCancellation(header)
        return try await request(.confirm(header), for: header)
    }

    public func cancel(_ header: WatchAudioHeader) async throws -> WatchAudioReceipt {
        let receipt = try await request(.cancel(header), for: header)
        guard receipt.isCancelled || receipt.isSavedAcknowledgement else {
            throw WatchExperimentError.resultUnknown
        }
        return receipt
    }
}
