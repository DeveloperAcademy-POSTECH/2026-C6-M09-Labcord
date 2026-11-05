import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

extension WatchRecordingUIBridge {
    static let live = Self(
        perform: { try await WatchRecordingService.shared.perform($0) },
        updates: { await WatchRecordingService.shared.updates() }
    )
}

/// 앱 수명 동안 캡처·복구를 유지한다. 화면 구독 취소는 녹음 중지가 아니다.
@MainActor
final class WatchRecordingService {
    static let shared = WatchRecordingService()
    let archive: WatchAudioArchive
    let recorder: WatchAudioRecorder
    let transfer: WatchAudioTransferClient
    var records: [UUID: WatchRecordPresentation] = [:]
    var observers: [UUID: AsyncStream<WatchRecordPresentation>.Continuation] = [:]
    var captureTasks: [UUID: Task<Void, Never>] = [:]
    private var voiceStartTasks: [UUID: Task<Void, Error>] = [:]
    var invalidatedVoiceStarts: Set<UUID> = []
    var receiptTask: Task<Void, Never>?
    var backgroundReceiptTask: Task<Void, Never>?
    var recordTask: Task<Void, Never>?
    var startup: Task<Void, Error>?
    var recordVersions: [UUID: UInt64] = [:]
    var transcriptVersions: [UUID: (generation: UUID, revision: UInt64)] = [:]
    var retiredGenerations: [UUID: Set<UUID>] = [:]

    @Dependency(\.watchConnectivitySession) var connectivity

    private init() {
        let archive = WatchAudioArchive(
            root: URL.applicationSupportDirectory.appending(path: "WatchAudioOutbox")
        )
        self.archive = archive
        recorder = WatchAudioRecorder(archive: archive)
        let exchange = WatchAudioImmediateExchange()
        transfer = WatchAudioTransferClient(archive: archive) { message in
            try await exchange.send(message)
        }
    }

    func activate() {
        guard startup == nil else { return }
        if receiptTask == nil { observeTransport() }
        startup = Task {
            do {
                try await recorder.recoverInterruptedRecordings()
                try await restoreLocalRecords()
                transfer.startRecovery()
            } catch {
                // 일시적인 복구 실패를 이후의 모든 녹음 요청에 고정하지 않는다.
                startup = nil
                throw error
            }
        }
    }

    func updates() -> AsyncStream<WatchRecordPresentation> {
        activate()
        let id = UUID()
        let bufferCount = max(64, records.count)
        return AsyncStream(bufferingPolicy: .bufferingNewest(bufferCount)) { continuation in
            observers[id] = continuation
            for record in records.values { continuation.yield(record) }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.observers[id] = nil }
            }
        }
    }

    func perform(_ input: WatchRecordingUIBridge.Input) async throws {
        if case let .cancelActiveVoiceForPause(_, recordID?) = input {
            invalidatedVoiceStarts.insert(recordID)
        }
        activate()
        do {
            try await startup?.value
        } catch {
            await rejectFailedStartup(input)
            throw error
        }
        switch input {
        case let .startVoice(experimentID, recordID):
            try await startVoiceUnlessCancelled(experimentID: experimentID, recordID: recordID)
        case let .startRemoteVoice(experimentID, recordID, expiresAt):
            try await startVoiceUnlessCancelled(
                experimentID: experimentID, recordID: recordID, expiresAt: expiresAt
            )
        case let .stopVoice(experimentID, recordID):
            try await stopVoice(experimentID: experimentID, recordID: recordID)
        case let .retry(experimentID, recordID):
            guard try await archive.headers().contains(where: {
                $0.experimentID == experimentID && $0.recordingID == recordID
            }) else { throw WatchAudioError.incomplete }
            try await restoreLocalRecords(recordID: recordID)
            await transfer.recover()
        case .reconcile:
            try await restoreLocalRecords()
            await transfer.recover()
        case let .stopForExperiment(experimentID):
            _ = try await recorder.stopForExperiment(experimentID)
            try await restoreLocalRecords()
            Task { await transfer.recover() }
        case let .cancelActiveVoiceForPause(experimentID, recordID):
            try await cancelActiveVoiceForPause(experimentID, recordID: recordID)
        }
    }

    private func cancelActiveVoiceForPause(_ experimentID: UUID, recordID: UUID?) async throws {
        if let active = recorder.activeRecording {
            guard active.experimentID == experimentID,
                  recordID == nil || active.recordingID == recordID else {
                throw WatchAudioError.conflict
            }
            transfer.prepareCancellation(active)
        }
        if let recordID, let starting = voiceStartTasks[recordID] {
            _ = try? await starting.value
        }
        if let active = recorder.activeRecording {
            guard active.experimentID == experimentID,
                  recordID == nil || active.recordingID == recordID else {
                throw WatchAudioError.conflict
            }
            transfer.prepareCancellation(active)
            captureTasks[active.recordingID]?.cancel()
            captureTasks[active.recordingID] = nil
            var record = records[active.recordingID] ?? WatchRecordPresentation(
                id: active.recordingID, experimentID: experimentID, kind: .voice
            )
            record.phase = .saving
            record.canAutoSave = false
            record.detail = "녹음 취소를 확인하고 있어요."
            publish(record)
            await recorder.stop()
            transfer.releaseCancellation(active)
        }
        let headers = try await archive.headers().filter {
            $0.experimentID == experimentID && (recordID == nil || $0.recordingID == recordID)
        }
        try await prepareInactiveVoiceCancellation(recordID, headers: headers)
        for header in headers where transfer.isCancellationPending(header) {
            transfer.releaseCancellation(header)
            _ = try await transfer.cancel(header)
        }
        if let recordID, !headers.contains(where: { $0.recordingID == recordID }) {
            var record = records[recordID] ?? WatchRecordPresentation(
                id: recordID, experimentID: experimentID, kind: .voice
            )
            guard record.experimentID == experimentID, !record.isSettled else { return }
            record.phase = .cancelled
            record.canAutoSave = false
            record.detail = "녹음을 시작하기 전에 취소했어요."
            publish(record)
        }
    }

    private func prepareInactiveVoiceCancellation(
        _ recordID: UUID?, headers: [WatchAudioHeader]
    ) async throws {
        // Only the explicitly selected in-flight record may acquire a new cancellation intent.
        guard let recordID, let header = headers.first(where: { $0.recordingID == recordID }),
              !transfer.isCancellationPending(header) else { return }
        let status = try await archive.status(header)
        guard status.savedRecordID == nil else { throw WatchAudioError.conflict }
        guard !status.isCancelled else { return }
        transfer.prepareCancellation(header)
        captureTasks[recordID]?.cancel()
        captureTasks[recordID] = nil
    }

    private func stopVoice(experimentID: UUID, recordID: UUID) async throws {
        guard !invalidatedVoiceStarts.contains(recordID) else { return }
        if let active = recorder.activeRecording {
            guard active.experimentID == experimentID, active.recordingID == recordID else {
                throw WatchAudioError.conflict
            }
            await recorder.stop()
        }
        guard !invalidatedVoiceStarts.contains(recordID) else { return }
        guard let header = try await archive.headers().first(where: {
            $0.experimentID == experimentID && $0.recordingID == recordID
        }) else { throw WatchAudioError.incomplete }
        guard !invalidatedVoiceStarts.contains(recordID) else { return }
        _ = try await archive.completeManifest(header)
        guard !invalidatedVoiceStarts.contains(recordID) else { return }
        try await restoreLocalRecords()
        Task { await transfer.recover() }
    }

    private func observeTransport() {
        receiptTask = Task { [weak self, transfer] in
            for await receipt in transfer.receipts() {
                guard let self else { return }
                await self.receiveAudio(receipt)
            }
        }
        backgroundReceiptTask = Task { [weak self, connectivity, transfer] in
            for await receipt in connectivity.audioReceipts() {
                do { try await transfer.receive(receipt) } catch {
                    self?.failed(receipt.header, detail: "수신 확인을 대조하지 못했어요. 원본은 유지해요.")
                }
            }
        }
        recordTask = Task { [weak self, connectivity] in
            for await snapshot in connectivity.records.stream() {
                guard let self, snapshot.kind != .audio,
                      let experimentID = snapshot.experimentID else { continue }
                self.receiveRecord(snapshot, experimentID: experimentID)
            }
        }
    }

    func publish(_ value: WatchRecordPresentation) {
        var value = value
        if let previous = records[value.id] {
            guard previous.experimentID == value.experimentID, previous.kind == value.kind,
                  !previous.isSettled || previous.canRecapture else { return }
            value.revision = previous.revision
            guard value != previous, previous.revision < UInt64.max else { return }
            value.revision += 1
        } else {
            value.revision = max(1, value.revision)
        }
        records[value.id] = value
        observers.values.forEach { $0.yield(value) }
    }
}

private extension WatchRecordingService {
    func rejectFailedStartup(_ input: WatchRecordingUIBridge.Input) async {
        switch input {
        case let .startVoice(experimentID, recordID),
             let .startRemoteVoice(experimentID, recordID, _):
            await rejectEmptyVoiceStart(experimentID: experimentID, recordID: recordID)
        default:
            break
        }
    }

    private func startVoiceUnlessCancelled(
        experimentID: UUID, recordID: UUID, expiresAt: Date? = nil
    ) async throws {
        guard !invalidatedVoiceStarts.contains(recordID) else { return }
        let task = Task { @MainActor in
            guard !self.invalidatedVoiceStarts.contains(recordID) else { return }
            try await self.startVoice(
                experimentID: experimentID, recordID: recordID, expiresAt: expiresAt
            )
        }
        voiceStartTasks[recordID] = task
        defer { voiceStartTasks[recordID] = nil }
        try await task.value
    }

    private func startVoice(
        experimentID: UUID, recordID: UUID, expiresAt: Date? = nil
    ) async throws {
        guard records[recordID] == nil else { throw WatchAudioError.conflict }
        let events: AsyncStream<WatchAudioCaptureEvent>
        do {
            events = try await recorder.start(
                experimentID: experimentID, recordingID: recordID, expiresAt: expiresAt
            )
        } catch {
            await rejectEmptyVoiceStart(experimentID: experimentID, recordID: recordID)
            throw error
        }
        captureTasks[recordID] = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { break }
                guard let self else { return }
                self.capture(event, experimentID: experimentID, recordID: recordID)
            }
            self?.captureTasks[recordID] = nil
        }
    }

    private func rejectEmptyVoiceStart(experimentID: UUID, recordID: UUID) async {
        // 보관 조회 성공과 활성 녹음 부재가 모두 확인돼야 새 녹음을 허용한다.
        guard recorder.activeRecording == nil,
              (try? await hasNoVoiceOriginal(recordID)) == true else { return }
        var rejected = WatchRecordPresentation(
            id: recordID, experimentID: experimentID, kind: .voice
        )
        rejected.phase = .failed
        rejected.captureRejectedBeforeStart = true
        rejected.detail = "녹음을 시작하지 못했어요. 권한·저장 공간·앱 상태를 확인해주세요."
        publish(rejected)
    }

    private func hasNoVoiceOriginal(_ recordID: UUID) async throws -> Bool {
        guard let header = try await archive.headers().first(where: {
            $0.recordingID == recordID
        }) else { return true }
        let status = try await archive.status(header)
        return status.receivedSequences.isEmpty && (status.manifest?.totalSamples ?? 0) == 0
    }

}
