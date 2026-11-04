import Foundation
import LabcordShared
import WatchConnectivity

/// Uses the core-owned, already activated WCSession; never installs another delegate.
@MainActor
public final class WatchAudioTransferClient {
    public typealias Exchange = @Sendable (WatchAudioMessage) async throws -> WatchAudioReceipt
    private let archive: WatchAudioArchive
    private let exchange: Exchange
    private var recovery: Task<Void, Never>?
    private var isRecovering = false
    public private(set) var lastError: WatchAudioError?
    public private(set) var lastDeliveryError: WatchExperimentError?
    private var observers: [UUID: AsyncStream<WatchAudioReceipt>.Continuation] = [:]
    private var lastReceipts: [UUID: WatchAudioReceipt] = [:]

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

    /// Also invoke on activation/reachability changes. A lost ACK is resolved by status query.
    public func recover() async {
        guard !isRecovering else { return }
        isRecovering = true
        defer { isRecovering = false }
        do {
            for header in try await archive.headers() {
                try Task.checkCancellation()
                try await recover(header)
            }
        } catch is CancellationError {
            return
        } catch {
            // Connectivity/unknown delivery are retryable, never evidence of non-execution.
            lastError = error as? WatchAudioError
            lastDeliveryError = (error as? WatchExperimentError) ?? .resultUnknown
            await enqueueBackgroundFiles()
        }
    }

    private func enqueueBackgroundFiles() async {
        guard WCSession.default.activationState == .activated else { return }
        do {
            for header in try await archive.headers() {
                let receipt = try await archive.status(header)
                guard receipt.savedRecordID == nil, !receipt.isCancelled else { continue }
                enqueueBackgroundControl(header, manifest: receipt.manifest)
                let remote = try await archive.remoteReceipt(header)
                let received = Set(remote?.receivedSequences ?? [])
                for sequence in receipt.receivedSequences where !received.contains(sequence) {
                    let outstanding = WCSession.default.outstandingFileTransfers
                    guard outstanding.count < 2 else { return }
                    let url = try await archive.retainedChunkURL(header, sequence: sequence)
                    guard !outstanding.contains(where: { $0.file.fileURL == url }) else {
                        continue
                    }
                    WCSession.default.transferFile(url, metadata: ["labcordAudioChunk": true])
                }
            }
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

    /// Core routes reply user-info here for background files and manifest/status messages.
    public func receive(_ receipt: WatchAudioReceipt) async throws {
        try await archive.rememberRemoteReceipt(receipt)
        if receipt.savedRecordID != nil { try await archive.acknowledgeSaved(receipt) }
        if receipt.isCancelled { _ = try await archive.cancel(receipt.header) }
        lastError = receipt.failure
        if lastReceipts[receipt.header.recordingID] != receipt {
            lastReceipts[receipt.header.recordingID] = receipt
            observers.values.forEach { $0.yield(receipt) }
        }
    }

    private func recover(_ header: WatchAudioHeader) async throws {
        let local = try await archive.status(header)
        guard local.savedRecordID == nil, !local.isCancelled else { return }
        var remote = try await exchange(.status(header))
        guard remote.header == header else { throw WatchAudioError.conflict }
        lastDeliveryError = nil
        try await receive(remote)
        if remote.isCancelled {
            _ = try await archive.cancel(header)
            return
        }
        let received = Set(remote.receivedSequences)
        for sequence in local.receivedSequences where !received.contains(sequence) {
            try Task.checkCancellation()
            remote = try await exchange(.chunk(archive.chunk(header, sequence)))
            guard remote.header == header else { throw WatchAudioError.conflict }
            try await receive(remote)
        }
        if let manifest = local.manifest {
            remote = try await exchange(.finish(manifest))
            guard remote.header == header else { throw WatchAudioError.conflict }
            try await receive(remote)
        }
        if remote.savedRecordID != nil {
            try await archive.acknowledgeSaved(remote)
        }
        if let failure = remote.failure { lastError = failure }
    }

    public func confirm(_ header: WatchAudioHeader) async throws -> WatchAudioReceipt {
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
        return receipt
    }
}

/// Install this exchange closure in WatchAudioTransferClient after core WC activation.
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
            WCSession.default.sendMessageData(data) { [weak self] reply in
                Task { @MainActor in
                    self?.resolve(id, result: Result {
                        try JSONDecoder().decode(WatchAudioReceipt.self, from: reply)
                    })
                }
            } errorHandler: { [weak self] error in
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
