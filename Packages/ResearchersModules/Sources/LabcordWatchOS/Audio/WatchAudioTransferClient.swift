import Foundation
import LabcordShared
import WatchConnectivity

@MainActor
public final class WatchAudioTransferClient {
    public typealias Exchange = @Sendable (WatchAudioMessage) async throws -> WatchAudioReceipt
    private let archive: WatchAudioArchive
    private let exchange: Exchange
    private var recovery: Task<Void, Never>?
    private var isRecovering = false
    public private(set) var lastError: WatchAudioError?
    public private(set) var lastDeliveryError: WatchExperimentError?

    public private(set) var damagedRecordingIDs: [UUID] = []
    private var observers: [UUID: AsyncStream<WatchAudioReceipt>.Continuation] = [:]
    private var verifiedObservers: [UUID: WeakWatchAudioVerifiedSaveObservation] = [:]
    private var lastReceipts: [UUID: WatchAudioReceipt] = [:]
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
        ids.remove(header.recordingID.uuidString)
        UserDefaults.standard.set(Array(ids), forKey: cancellationKey)
    }

    private func checkCancellation(_ header: WatchAudioHeader) throws {
        if isCancellationPending(header) { throw CancellationError() }
    }

    public init(archive: WatchAudioArchive, exchange: @escaping Exchange) {
        self.archive = archive
        self.exchange = exchange
    }

    deinit { recovery?.cancel() }

    public func receipts() -> AsyncStream<WatchAudioReceipt> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<WatchAudioReceipt>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
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
    }

    public func recover() async {
        guard !isRecovering else { return }
        isRecovering = true
        defer { isRecovering = false }
        var shouldEnqueueBackground = false
        do {
            try await WatchAudioRecoveryRunner.forEach(
                try await scanArchiveHeaders(), process: { header in
                    if self.isCancellationPending(header) {
                        guard !self.deferredCancellations.contains(header.recordingID)
                        else { return }
                        _ = try await self.cancel(header)
                        return
                    }
                    try await self.recover(header)
                }, onError: { error in
                    guard !(error is CancellationError) else { return }
                    self.lastError = (error as? WatchAudioError) ?? .interrupted
                    if !(error is WatchAudioError) {
                        self.lastDeliveryError = (error as? WatchExperimentError) ?? .resultUnknown
                        shouldEnqueueBackground = true
                    }
                }
            )
            if shouldEnqueueBackground { await enqueueBackgroundFiles() }
        } catch is CancellationError {
            return
        } catch {

            lastError = error as? WatchAudioError
            lastDeliveryError = (error as? WatchExperimentError) ?? .resultUnknown
            await enqueueBackgroundFiles()
        }
    }

    private func scanArchiveHeaders() async throws -> [WatchAudioHeader] {
        let scan = try await archive.scanHeaders()
        damagedRecordingIDs = scan.damagedRecordingIDs
        if !damagedRecordingIDs.isEmpty { lastError = .invalidAudio }
        return scan.headers
    }

    private func enqueueBackgroundFiles() async {
        guard WCSession.default.activationState == .activated else { return }
        do {
            try await WatchAudioRecoveryRunner.forEach(
                try await scanArchiveHeaders(), process: { header in
                    guard !self.isCancellationPending(header) else { return }
                    let receipt = try await self.archive.statusEnsuringArchive(header)
                    guard receipt.savedRecordID == nil, !receipt.isCancelled else { return }
                    self.enqueueBackgroundControl(header, manifest: receipt.manifest)
                    let remote = try await self.archive.remoteReceipt(header)
                    let received = Set(remote?.receivedSequences ?? [])
                    for sequence in receipt.receivedSequences where !received.contains(sequence) {
                        let outstanding = WCSession.default.outstandingFileTransfers
                        guard outstanding.count < 2 else { return }
                        let url = try await self.archive.retainedChunkURL(
                            header, sequence: sequence
                        )
                        guard !outstanding.contains(where: { $0.file.fileURL == url })
                        else { continue }
                        WCSession.default.transferFile(url, metadata: ["labcordAudioChunk": true])
                    }
                }, onError: { error in
                    self.lastError = (error as? WatchAudioError) ?? .interrupted
                }
            )
        } catch { lastError = (error as? WatchAudioError) ?? .interrupted }
    }

    private func enqueueBackgroundControl(
        _ header: WatchAudioHeader, manifest: WatchAudioManifest?
    ) {
        guard WCSession.default.outstandingUserInfoTransfers.count < 2 else { return }
        let message = manifest.map(WatchAudioMessage.finish) ?? .status(header)
        if let data = try? JSONEncoder().encode(message) {
            WCSession.default.transferUserInfo(["labcordAudioMessage": data])
        }
    }

    public func receive(_ receipt: WatchAudioReceipt) async throws {
        guard !isCancellationPending(receipt.header) || receipt.isCancelled else { return }
        if !receipt.isCancelled,
           try await archive.statusEnsuringArchive(receipt.header).isCancelled { return }
        try await archive.rememberRemoteReceipt(receipt)

        if receipt.savedRecordID != nil { startRecovery() }
        if receipt.isCancelled { _ = try await archive.cancel(receipt.header) }
        lastError = receipt.failure ?? (damagedRecordingIDs.isEmpty ? nil : .invalidAudio)
        if lastReceipts[receipt.header.recordingID] != receipt {
            lastReceipts[receipt.header.recordingID] = receipt
            observers.values.forEach { $0.yield(receipt) }
        }
    }

    private func recover(_ header: WatchAudioHeader) async throws {
        try checkCancellation(header)
        let local = try await archive.statusEnsuringArchive(header)
        if local.savedRecordID != nil {
            if try await archive.needsSavedCleanup(header) { try await refreshSaved(header) }
            return
        }
        try await recoverUnsaved(header, local: local)
    }

    private func recoverUnsaved(
        _ header: WatchAudioHeader, local: WatchAudioReceipt
    ) async throws {
        guard !local.isCancelled else { return }
        var remote = try await exchange(.status(header))
        try checkCancellation(header)
        guard remote.header == header else { throw WatchAudioError.conflict }
        lastDeliveryError = nil
        try await receive(remote)
        if remote.savedRecordID != nil {
            try await refreshSaved(header)
            return
        }
        if remote.isCancelled {
            _ = try await archive.cancel(header)
            return
        }
        let received = Set(remote.receivedSequences)
        for sequence in local.receivedSequences where !received.contains(sequence) {
            try Task.checkCancellation()
            try checkCancellation(header)
            remote = try await exchange(.chunk(archive.chunk(header, sequence)))
            try checkCancellation(header)
            guard remote.header == header else { throw WatchAudioError.conflict }
            try await receive(remote)
        }
        if let manifest = local.manifest {
            try checkCancellation(header)
            remote = try await exchange(.finish(manifest))
            try checkCancellation(header)
            guard remote.header == header else { throw WatchAudioError.conflict }
            try await receive(remote)
        }
        if remote.savedRecordID != nil {
            try await refreshSaved(header)
        }
        if let failure = remote.failure { lastError = failure }
    }

    private func refreshSaved(_ header: WatchAudioHeader) async throws {
        let receipt = try await verifySaved(header)
        publishVerified(receipt)
    }

    public func verifySaved(_ header: WatchAudioHeader) async throws -> WatchAudioReceipt {
        var verified: WatchAudioReceipt?
        try await WatchAudioRecoveryRunner.refreshSaved(header, query: exchange) { receipt in
            try self.checkCancellation(header)
            try await self.archive.rememberRemoteReceipt(receipt)
            try await self.archive.acknowledgeSavedAndCleanUp(receipt)
            try await self.receive(receipt)
            verified = receipt
        }
        guard let verified else { throw WatchAudioError.incomplete }
        return verified
    }

    public func confirm(_ header: WatchAudioHeader) async throws -> WatchAudioReceipt {
        guard !isCancellationPending(header) else { throw WatchAudioError.conflict }
        let receipt = try await exchange(.confirm(header))
        guard receipt.header == header else { throw WatchAudioError.conflict }
        try await receive(receipt)
        return receipt
    }

    public func cancel(_ header: WatchAudioHeader) async throws -> WatchAudioReceipt {
        let receipt = try await exchange(.cancel(header))
        guard receipt.header == header, receipt.isCancelled else {
            throw WatchAudioError.conflict
        }
        try await receive(receipt)
        clearCancellation(header)
        return receipt
    }
}

@MainActor
public final class WatchAudioImmediateExchange {
    private var pending: [UUID: CheckedContinuation<WatchAudioReceipt, Error>] = [:]

    public init() {}

    public func send(_ message: WatchAudioMessage) async throws -> WatchAudioReceipt {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { throw WatchExperimentError.notReachable }
        let data = try JSONEncoder().encode(message)
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            WCSession.default.sendMessageData(data) { @Sendable [weak self] reply in
                Task { @MainActor in
                    self?.resolve(id, result: Result {
                        try JSONDecoder().decode(WatchAudioReceipt.self, from: reply)
                    })
                }
            } errorHandler: { @Sendable [weak self] error in
                Task { @MainActor in self?.resolve(id, result: .failure(error)) }
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.resolve(id, result: .failure(WatchExperimentError.deliveryTimeout))
            }
        }
    }

    private func resolve(_ id: UUID, result: Result<WatchAudioReceipt, Error>) {
        pending.removeValue(forKey: id)?.resume(with: result)
    }
}
