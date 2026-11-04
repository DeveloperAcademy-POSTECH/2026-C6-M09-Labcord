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
        observeTransport()
        startup = Task {
            try await recorder.recoverInterruptedRecordings()
            try await restoreLocalRecords()
            transfer.startRecovery()
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
        activate()
        try await startup?.value
        switch input {
        case let .startVoice(experimentID, recordID):
            try await startVoice(experimentID: experimentID, recordID: recordID)
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
        }
    }

    private func startVoice(experimentID: UUID, recordID: UUID) async throws {
        guard records[recordID] == nil else { throw WatchAudioError.conflict }
        let events: AsyncStream<WatchAudioCaptureEvent>
        do {
            events = try await recorder.start(experimentID: experimentID, recordingID: recordID)
        } catch {
            // 보관 조회 성공과 활성 녹음 부재가 모두 확인돼야 새 녹음을 허용한다.
            if recorder.activeRecording == nil,
               (try? await hasNoVoiceOriginal(recordID)) == true {
                var rejected = WatchRecordPresentation(
                    id: recordID, experimentID: experimentID, kind: .voice
                )
                rejected.phase = .failed
                rejected.captureRejectedBeforeStart = true
                rejected.detail = "녹음을 시작하지 못했어요. 권한·저장 공간·앱 상태를 확인해주세요."
                publish(rejected)
            }
            throw error
        }
        captureTasks[recordID] = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.capture(event, experimentID: experimentID, recordID: recordID)
            }
            self?.captureTasks[recordID] = nil
        }
    }

    private func hasNoVoiceOriginal(_ recordID: UUID) async throws -> Bool {
        guard let header = try await archive.headers().first(where: {
            $0.recordingID == recordID
        }) else { return true }
        let status = try await archive.status(header)
        return status.receivedSequences.isEmpty && (status.manifest?.totalSamples ?? 0) == 0
    }

    private func stopVoice(experimentID: UUID, recordID: UUID) async throws {
        if let active = recorder.activeRecording {
            guard active.experimentID == experimentID, active.recordingID == recordID else {
                throw WatchAudioError.conflict
            }
            await recorder.stop()
        }
        guard let header = try await archive.headers().first(where: {
            $0.experimentID == experimentID && $0.recordingID == recordID
        }) else { throw WatchAudioError.incomplete }
        _ = try await archive.completeManifest(header)
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
                  !previous.isSettled else { return }
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
