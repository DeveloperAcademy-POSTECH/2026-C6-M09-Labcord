import ComposableArchitecture
import Foundation
import LabcordShared
import Observation

@MainActor
@Observable
public final class PhoneWatchAudioService {
    public static let shared = PhoneWatchAudioService()
    public static let messageKey = "labcordAudioMessage"
    public static let receiptKey = "labcordAudioReceipt"

    private let archive: WatchAudioArchive
    private let receiver: WatchAudioReceiver
    private let connectivity: WatchConnectivitySession
    private let revisionURL: URL
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var transcripts: Task<Void, Never>?
    private var latest: [UUID: WatchAudioReceipt] = [:]
    @ObservationIgnored private lazy var verificationJobs = makeVerificationJobs()
    public struct LiveRecording: Equatable {
        public let experimentID: UUID
        public let recordingID: UUID
        public let startedAt: Date
        public let expiresAt: Date
    }

    public private(set) var liveRecording: LiveRecording?
    private var screenState = WatchRecordingScreenState()
    private var hasScannedInbox = false
    public var screenRecording: WatchScreenRecording? { screenState.recording }

    public func hasUnsettledRecording(in experimentID: UUID? = nil) -> Bool {
        !hasScannedInbox || screenState.hasUnsettledRecording(in: experimentID)
    }

    public func isCapturing(in experimentID: UUID, at now: Date = .now) -> Bool {
        guard let liveRecording else { return false }
        return liveRecording.experimentID == experimentID && liveRecording.expiresAt > now
    }

    func requireSettledRecording(in experimentID: UUID) throws {
        guard !hasUnsettledRecording(in: experimentID) else {
            throw WatchExperimentError.phoneBusy
        }
    }

    private var lastLiveStatusAt: [UUID: Date] = [:]
    public private(set) var lastError: WatchAudioError?

    public private(set) var damagedRecordingIDs: [UUID] = []

    public init() {
        @Dependency(\.experimentClient) var client
        @Dependency(\.watchConnectivitySession) var connectivity
        let root = URL.applicationSupportDirectory.appending(path: "WatchAudioInbox")
        let archive = WatchAudioArchive(root: root)
        self.archive = archive
        self.connectivity = connectivity
        revisionURL = root.appending(path: "record-revision.txt")
        let loadSessionDetail: @MainActor (UUID) throws -> ExperimentSessionDetail = { id in
            guard let state = try client.watchState(id) else {
                throw WatchExperimentError.experimentNotFound
            }
            return state.detail
        }
        receiver = WatchAudioReceiver(
            archive: archive, client: client, locale: Locale(identifier: "ko-KR"),
            sessionDetail: loadSessionDetail
        )
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
        while !Task.isCancelled {
            do {
                expireLiveRecording(at: .now)
                if hasScannedInbox {
                    await receiver.retryRetainedFiles()
                } else {
                    try await receiver.recover()
                }
                let scan = try await archive.scanHeaders()
                damagedRecordingIDs = scan.damagedRecordingIDs
                if !damagedRecordingIDs.isEmpty { lastError = .invalidAudio }
                for header in scan.headers {
                    try Task.checkCancellation()
                    do {
                        try await refreshIfNeeded(header)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        lastError = (error as? WatchAudioError) ?? .storageFailed
                    }
                }
                hasScannedInbox = true
                try await Task.sleep(for: .seconds(1))
            } catch is CancellationError {
                return
            } catch {
                lastError = (error as? WatchAudioError) ?? .storageFailed
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    private func refreshIfNeeded(_ header: WatchAudioHeader) async throws {
        if let receipt = latest[header.recordingID] {
            if receipt.isCancelled { return }
            if receipt.savedRecordID != nil, receipt.contentDigest != nil,
               try await !archive.needsSavedCleanup(header) { return }
        }
        await refresh(header)
    }

    private func makeVerificationJobs() -> WatchSavedVerificationJobs {
        WatchSavedVerificationJobs { [weak self] header, challenge, progress in
            guard let self else { throw WatchAudioError.storageFailed }
            let input = try JSONEncoder().encode(WatchAudioMessage.verifySaved(header, challenge))
            return try await self.receiver.receive(input, verificationProgress: progress)
        }
    }

    public func receive(_ data: Data) async throws -> Data {
        activate()
        guard data.count <= 200_000 else { throw WatchAudioError.invalidAudio }
        let message = try JSONDecoder().decode(WatchAudioMessage.self, from: data)
        switch message {
        case let .beginSavedVerification(header, challenge):
            return try verificationJobs.begin(header, challenge: challenge)
        case let .savedVerificationResult(header, challenge):
            return try verificationJobs.result(header, challenge: challenge)
        case .verifySaved:
            return try await receiver.receive(data)
        default:
            let receipt = try await receiver.receive(message)
            return try JSONEncoder().encode(canonicalReceipt(receipt))
        }
    }

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
        sendReceipt(try canonicalReceipt(receipt))
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
        let receipt = try await receiver.currentReceipt(header)
        let record = makeRecord(try canonicalReceipt(receipt))
        return WatchExperimentResponse(
            requestID: response.requestID, phase: response.phase,
            error: response.error, record: record
        )
    }

    private func refresh(_ header: WatchAudioHeader) async {
        do {
            _ = try canonicalReceipt(await receiver.currentReceipt(header))
        } catch { lastError = (error as? WatchAudioError) ?? .storageFailed }
    }

    private func canonicalReceipt(_ receipt: WatchAudioReceipt) throws -> WatchAudioReceipt {
        let id = receipt.header.recordingID
        if let previous = latest[id],
           let revision = recordRevisions[id],
           previous == receipt || !receipt.canReplace(previous) {
            return previous.withStateRevision(revision)
        }
        if receipt.savedRecordID == nil, !receipt.isCancelled,
           receipt.receivedSequences.isEmpty, receipt.manifest == nil {
            return receipt
        }
        if let saved = receipt.savedRecordID, saved != id { throw WatchAudioError.conflict }
        let elapsed = receipt.manifest.map {
            Double($0.totalSamples) / Double($0.header.sampleRate)
        }
        screenState.receive(makeRecord(receipt), elapsedSeconds: elapsed)
        if phase(receipt) != .recording, liveRecording?.recordingID == id {
            liveRecording = nil
        }
        let revision = try nextRevision()
        latest[id] = receipt
        recordRevisions[id] = revision
        let stamped = receipt.withStateRevision(revision)
        let record = makeRecord(stamped)
        Task { [weak self] in
            guard let self, recordRevisions[id] == revision,
                  record.epoch == PhoneWatchExperimentCoordinator.shared.stateEpoch
            else { return }
            connectivity.records.publish(record, session: connectivity.session)
            PhoneWatchExperimentCoordinator.shared.recordDidChange(record)
            if receipt.isSavedAcknowledgement || receipt.isCancelled || receipt.isReviewing
                || receipt.failure != nil {
                sendReceipt(stamped)
            }
        }
        return stamped
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
}

private extension PhoneWatchAudioService {
    func expireLiveRecording(at now: Date) {
        if let liveRecording, liveRecording.expiresAt <= now { self.liveRecording = nil }
        let previous = screenState.recording
        screenState.expireCaptures(at: now)
        if let previous, screenState.recording == nil {
            PhoneWatchExperimentCoordinator.shared.recordDidChange(WatchRecordSnapshot(
                id: previous.id, kind: .audio, phase: .failed,
                experimentID: previous.experimentID
            ))
        }
    }

    func makeRecord(_ receipt: WatchAudioReceipt) -> WatchRecordSnapshot {
        WatchRecordSnapshot(
            id: receipt.header.recordingID, kind: .audio, phase: phase(receipt),
            startedAt: receipt.header.startedAt, canAutoSave: receipt.isReviewing,
            experimentID: receipt.header.experimentID, revision: receipt.stateRevision ?? 0,
            transcript: receipt.transcript?.text, isFinalTranscript: receipt.transcript?.isFinal,
            originalRetained: receipt.manifest != nil || !receipt.receivedSequences.isEmpty,
            error: receipt.failure?.watchExperimentError,
            epoch: PhoneWatchExperimentCoordinator.shared.stateEpoch
        )
    }

    func phase(_ receipt: WatchAudioReceipt) -> WatchRecordSnapshot.Phase {
        if receipt.isSavedAcknowledgement { return .saved }
        if receipt.isCancelled { return .cancelled }
        if receipt.failure != nil { return .failed }
        if receipt.isReviewing { return .review }
        return receipt.manifest == nil ? .recording : .previewing
    }
}

extension PhoneWatchAudioService {
    public func canSaveReviewedRecordings(in experimentID: UUID) -> Bool {
        latest.values.contains { isReviewedRecording($0, in: experimentID) }
    }

    public func saveReviewedRecordings(in experimentID: UUID) async throws {
        for receipt in latest.values.filter({ isReviewedRecording($0, in: experimentID) }) {
            let command = WatchExperimentCommand(
                operation: .confirmRecord, experimentID: experimentID,
                targetID: receipt.header.recordingID, recordKind: .audio
            )
            let response = try await handleRecordCommand(command)
            guard response.record?.phase == .saved else { throw WatchAudioError.incomplete }
        }
    }

    private func isReviewedRecording(_ receipt: WatchAudioReceipt, in experimentID: UUID) -> Bool {
        receipt.header.experimentID == experimentID && receipt.isReviewing
            && receipt.transcript?.isFinal == true && receipt.failure == nil
            && !receipt.isCancelled && receipt.savedRecordID == nil
    }

    public func dismissFinishedScreenRecording() {
        screenState.dismissFinishedRecording()
    }

    public func receiveLiveStatus(_ data: Data, receivedAt: Date = .now) {
        guard data.count <= 4096,
              let status = try? JSONDecoder().decode(WatchVoiceLiveStatus.self, from: data)
        else { return }
        guard status.phase != .cancelled,
              status.sentAt > lastLiveStatusAt[status.recordingID, default: .distantPast],
              status.sentAt <= receivedAt.addingTimeInterval(2),
              status.sentAt > receivedAt.addingTimeInterval(-3),
              status.startedAt <= status.sentAt,
              status.elapsedSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true,
              latest[status.recordingID]?.savedRecordID == nil,
              latest[status.recordingID]?.failure == nil,
              !status.isRecording || latest[status.recordingID]?.manifest == nil,
              latest[status.recordingID]?.isCancelled != true else { return }
        lastLiveStatusAt[status.recordingID] = status.sentAt
        if status.isRecording {
            liveRecording = LiveRecording(
                experimentID: status.experimentID, recordingID: status.recordingID,
                startedAt: status.startedAt, expiresAt: status.sentAt.addingTimeInterval(3)
            )
        } else if liveRecording?.recordingID == status.recordingID {
            liveRecording = nil
        }
        let previous = screenState.recording
        screenState.receive(status)
        if previous != screenState.recording {
            PhoneWatchExperimentCoordinator.shared.recordDidChange(WatchRecordSnapshot(
                id: status.recordingID, kind: .audio,
                phase: screenState.recording?.phase ?? .recording,
                experimentID: status.experimentID
            ))
        }
    }
}

private extension WatchAudioMessage {
    var header: WatchAudioHeader {
        switch self {
        case let .chunk(chunk): chunk.header
        case let .finish(manifest): manifest.header
        case let .status(header), let .verifySaved(header, _),
             let .beginSavedVerification(header, _), let .savedVerificationResult(header, _),
             let .confirm(header),
             let .cancel(header): header
        }
    }
}

extension PhoneWatchAudioService {
    var canResetDebugData: Bool {
        !hasUnsettledRecording() && receiver.processing.isEmpty
    }

    func clearDebugData() {
        receiver.clearDebugData()
        latest.removeAll()
        recordRevisions.removeAll()
        liveRecording = nil
        screenState = WatchRecordingScreenState()
        lastLiveStatusAt.removeAll()
        lastError = nil
        damagedRecordingIDs.removeAll()
    }
}
