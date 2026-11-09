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

@MainActor
final class WatchRecordingService {
    static let shared = WatchRecordingService()
    let archive: WatchAudioArchive
    let recorder: WatchAudioRecorder
    let transfer: WatchAudioTransferClient
    var records: [UUID: WatchRecordPresentation] = [:]
    var observers: [UUID: AsyncStream<WatchRecordPresentation>.Continuation] = [:]
    var captureTasks: [UUID: Task<Void, Never>] = [:]
    var voiceStatusTasks: [UUID: Task<Void, Never>] = [:]
    var voiceStartTasks: [UUID: Task<Void, Error>] = [:]
    var pendingVoiceStarts: Set<UUID> = []
    var closingExperiments: Set<UUID> = []
    var invalidatedVoiceStarts: Set<UUID> = []
    var receiptTask: Task<Void, Never>?
    var verifiedReceiptTask: Task<Void, Never>?
    var verifiedSavedReceipts: [UUID: WatchAudioReceipt] = [:]
    var savedVerificationTasks: [UUID: Task<Void, Never>] = [:]
    struct RetentionCacheEntry {
        let status: WatchAudioReceipt
        let retention: WatchAudioLocalRetention
    }
    var retentionCache: [UUID: RetentionCacheEntry] = [:]
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

                startup = nil
                throw error
            }
        }
    }

    func updates() -> AsyncStream<WatchRecordPresentation> {
        activate()
        let savedVoices = records.values.filter { $0.kind == .voice && $0.phase == .saved }
        for current in savedVoices {
            let receipt = verifiedSavedReceipts.removeValue(forKey: current.id)
            var record = current
            if let receipt {
                record.phase = .saving
                record.requiresSavedVerification = true
                record.detail = "iPhone의 저장 원본을 다시 확인하고 있어요."
                publish(record)
                requestSavedVerification(receipt.header)
            } else {
                record.phase = .failed
                record.detail = "저장 확인 정보를 찾지 못했어요. 상태를 다시 확인해주세요."
                publish(record)
            }
        }
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
        let reservedStartID = try reserveVoiceStart(input)
        defer {
            if let reservedStartID { pendingVoiceStarts.remove(reservedStartID) }
        }
        markCancelledStart(input)
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
            try await finishVoiceForExperiment(experimentID)
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

        guard let recordID, let header = headers.first(where: { $0.recordingID == recordID }),
              !transfer.isCancellationPending(header) else { return }
        let status = try await archive.statusEnsuringArchive(header)
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
        let observation = transfer.observeVerifiedSaves()
        verifiedReceiptTask = Task { [weak self] in
            defer { observation.cancel() }
            for await receipt in observation.receipts {
                guard let self else { continue }
                await self.receiveVerifiedSaved(receipt)
                if observation.consumeReconciliationNeeded() {
                    await self.reconcileUnresolvedSavedRecords()
                }
            }
        }
        receiptTask = Task { [weak self, transfer] in
            for await receipt in transfer.receipts() {
                guard let self else { return }
                await self.receiveAudio(receipt)
            }
        }
        backgroundReceiptTask = Task { [weak self, connectivity, transfer] in
            for await receipt in connectivity.audioReceipts() {
                do { try await transfer.receive(receipt) } catch {
                    self?.failed(receipt.header, detail: "수신 확인을 대조하지 못했어요. 보관 상태를 확인해주세요.")
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
                  !previous.isSettled || previous.canRecapture
                    || (value.kind == .voice && previous.phase == .saved
                        && (value.phase == .saving || value.phase == .failed))
            else { return }
            value.revision = previous.revision
            guard value != previous, previous.revision < UInt64.max else { return }
            value.revision += 1
        } else {
            value.revision = max(1, value.revision)
        }
        records[value.id] = value
        updateVoiceLiveStatus(value)
        observers.values.forEach { $0.yield(value) }
    }

}

private extension WatchRecordingService {
    func reserveVoiceStart(_ input: WatchRecordingUIBridge.Input) throws -> UUID? {
        switch input {
        case let .startVoice(_, recordID), let .startRemoteVoice(_, recordID, _):
            guard closingExperiments.isEmpty, pendingVoiceStarts.insert(recordID).inserted else {
                throw WatchAudioError.conflict
            }
            return recordID
        default:
            return nil
        }
    }

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
        guard closingExperiments.isEmpty || pendingVoiceStarts.contains(recordID) else {
            throw WatchAudioError.conflict
        }
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
        let status = try await archive.statusEnsuringArchive(header)
        return status.receivedSequences.isEmpty && (status.manifest?.totalSamples ?? 0) == 0
    }

}
