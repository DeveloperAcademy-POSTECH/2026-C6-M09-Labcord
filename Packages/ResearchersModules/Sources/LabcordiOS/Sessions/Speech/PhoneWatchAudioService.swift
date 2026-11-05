import ComposableArchitecture
import Foundation
import LabcordShared

/// 앱 수명의 수신기다. UI 진입 없이 보관·전사·최종 저장 확인을 복구한다.
@MainActor
public final class PhoneWatchAudioService {
    public static let shared = PhoneWatchAudioService()
    public static let messageKey = "labcordAudioMessage"
    public static let receiptKey = "labcordAudioReceipt"

    private let archive: WatchAudioArchive
    private let receiver: WatchAudioReceiver
    private let connectivity: WatchConnectivitySession
    private let revisionURL: URL
    private var monitor: Task<Void, Never>?
    private var transcripts: Task<Void, Never>?
    private var latest: [UUID: WatchAudioReceipt] = [:]
    public private(set) var lastError: WatchAudioError?

    public init() {
        @Dependency(\.experimentClient) var client
        @Dependency(\.watchConnectivitySession) var connectivity
        let root = URL.applicationSupportDirectory.appending(path: "WatchAudioInbox")
        let archive = WatchAudioArchive(root: root)
        self.archive = archive
        self.connectivity = connectivity
        revisionURL = root.appending(path: "record-revision.txt")
        receiver = WatchAudioReceiver(archive: archive, client: client) { id in
            guard let state = try client.watchState(id) else {
                throw WatchExperimentError.experimentNotFound
            }
            return state.detail.speechContextualStrings
        }
    }

    deinit {
        monitor?.cancel()
        transcripts?.cancel()
    }

    public func activate() {
        guard monitor == nil else { return }
        transcripts = Task { [weak self] in
            guard let self else { return }
            for await transcript in self.receiver.transcripts() {
                guard !Task.isCancelled else { return }
                await self.refresh(transcript.header)
            }
        }
        monitor = Task { [weak self] in
            await self?.monitorRecords()
        }
    }

    private func monitorRecords() async {
        do { try await receiver.recover() } catch {
            lastError = (error as? WatchAudioError) ?? .storageFailed
        }
        while !Task.isCancelled {
            do {
                for header in try await archive.headers() {
                    try Task.checkCancellation()
                    if latest[header.recordingID]?.savedRecordID != nil
                        || latest[header.recordingID]?.isCancelled == true { continue }
                    await refresh(header)
                }
                try await Task.sleep(for: .seconds(1))
            } catch is CancellationError {
                return
            } catch {
                lastError = (error as? WatchAudioError) ?? .storageFailed
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    public func receive(_ data: Data) async throws -> Data {
        activate()
        let reply = try await receiver.receive(data)
        let receipt = try JSONDecoder().decode(WatchAudioReceipt.self, from: reply)
        try publish(receipt)
        return reply
    }

    /// WCSession replyHandler에는 throw를 전달할 수 없어 실패 receipt로 응답한다.
    public func reply(to data: Data) async -> Data {
        do { return try await receive(data) } catch {
            lastError = (error as? WatchAudioError) ?? .storageFailed
            guard data.count <= 200_000,
                  let message = try? JSONDecoder().decode(WatchAudioMessage.self, from: data)
            else { return Data() }
            let receipt = WatchAudioReceipt(
                header: message.header, receivedSequences: [], manifest: nil,
                failure: lastError
            )
            return (try? JSONEncoder().encode(receipt)) ?? Data()
        }
    }

    public func receiveRetainedFile(_ url: URL) async throws {
        activate()
        let receipt = try await receiver.receiveRetainedFile(url)
        try publish(receipt)
        sendReceipt(receipt)
    }

    public func containsRecord(experimentID: UUID, recordID: UUID) async throws -> Bool {
        let headers = try await archive.headers()
        guard let header = headers.first(where: { $0.recordingID == recordID }) else {
            return false
        }
        guard header.experimentID == experimentID else { throw WatchAudioError.conflict }
        return true
    }

    public func handleRecordCommand(
        _ command: WatchExperimentCommand
    ) async throws -> WatchExperimentResponse {
        let response = try await receiver.handleRecordCommand(command)
        guard let id = command.targetID,
              let header = try await archive.headers().first(where: { $0.recordingID == id })
        else { throw WatchAudioError.conflict }
        let message = try JSONEncoder().encode(WatchAudioMessage.status(header))
        let data = try await receiver.receive(message)
        let receipt = try JSONDecoder().decode(WatchAudioReceipt.self, from: data)
        let record = try publish(receipt)
        return WatchExperimentResponse(
            requestID: response.requestID, phase: response.phase,
            error: response.error, record: record
        )
    }

    private func refresh(_ header: WatchAudioHeader) async {
        do {
            let message = try JSONEncoder().encode(WatchAudioMessage.status(header))
            let data = try await receiver.receive(message)
            _ = try publish(JSONDecoder().decode(WatchAudioReceipt.self, from: data))
        } catch { lastError = (error as? WatchAudioError) ?? .storageFailed }
    }

    @discardableResult
    private func publish(_ receipt: WatchAudioReceipt) throws -> WatchRecordSnapshot {
        let recordID = receipt.header.recordingID
        if receipt.hasTranscriptConflict == true {
            guard let transcript = receipt.transcript, transcript.header == receipt.header,
                  transcript.isFinal else { throw WatchAudioError.conflict }
        }
        if let saved = receipt.savedRecordID, saved != recordID { throw WatchAudioError.conflict }
        let changed = latest[recordID] != receipt
        let revision = changed ? try nextRevision() : recordRevisions[recordID] ?? 0
        let record = WatchRecordSnapshot(
            id: recordID, kind: .audio, phase: phase(receipt),
            startedAt: receipt.header.startedAt, canAutoSave: receipt.isReviewing,
            experimentID: receipt.header.experimentID, revision: revision,
            transcript: receipt.transcript?.text, isFinalTranscript: receipt.transcript?.isFinal,
            originalRetained: !receipt.receivedSequences.isEmpty,
            error: receipt.failure.map { error in
                error == .permissionDenied ? .permissionDenied : .storageFailed
            }
        )
        if changed {
            latest[recordID] = receipt
            recordRevisions[recordID] = revision
            connectivity.records.publish(record, session: connectivity.session)
            if receipt.savedRecordID != nil || receipt.isCancelled || receipt.isReviewing
                || receipt.failure != nil {
                sendReceipt(receipt)
            }
        }
        return record
    }

    private func sendReceipt(_ receipt: WatchAudioReceipt) {
        if let data = try? JSONEncoder().encode(receipt) {
            connectivity.transferUserInfo([Self.receiptKey: data])
        }
    }

    private var recordRevisions: [UUID: UInt64] = [:]

    private func nextRevision() throws -> UInt64 {
        var previous: UInt64 = 0
        if FileManager.default.fileExists(atPath: revisionURL.path) {
            let data = try Data(contentsOf: revisionURL)
            guard let value = String(data: data, encoding: .utf8).flatMap(UInt64.init),
                  value < UInt64.max else { throw WatchAudioError.storageFailed }
            previous = value
        }
        let next = previous + 1
        try FileManager.default.createDirectory(
            at: revisionURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(String(next).utf8).write(
            to: revisionURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        return next
    }

    private func phase(_ receipt: WatchAudioReceipt) -> WatchRecordSnapshot.Phase {
        if receipt.savedRecordID != nil { return .saved }
        if receipt.isCancelled { return .cancelled }
        if receipt.failure != nil { return .failed }
        if receipt.isReviewing { return .review }
        return receipt.manifest == nil ? .recording : .previewing
    }
}

private extension WatchAudioMessage {
    var header: WatchAudioHeader {
        switch self {
        case let .chunk(chunk): chunk.header
        case let .finish(manifest): manifest.header
        case let .status(header), let .confirm(header), let .cancel(header): header
        }
    }
}
