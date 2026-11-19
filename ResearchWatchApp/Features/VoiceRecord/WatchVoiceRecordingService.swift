import AVFoundation
import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS
import WatchConnectivity

@MainActor
final class WatchVoiceRecordingService {
    static let shared = WatchVoiceRecordingService()

    private let recorder: WatchAudioRecorder
    private let archive: WatchAudioArchive
    private let transfer: WatchAudioTransferClient
    private let connectivity: WatchConnectivitySession
    private var incomingReceipts: Task<Void, Never>?
    private var startupRecovery: Task<Void, Never>?
    private var liveStatusTask: Task<Void, Never>?
    private var liveHeader: WatchAudioHeader?
    var activeRecording: WatchAudioHeader? { recorder.activeRecording }

    private init() {
        @Dependency(\.watchConnectivitySession) var connectivity
        self.connectivity = connectivity
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

    func start(
        experimentID: UUID, recordingID: UUID
    ) async throws -> AsyncStream<WatchAudioCaptureEvent> {
        activate()
        await startupRecovery?.value
        try Task.checkCancellation()
        guard await microphonePermission() else { throw WatchAudioError.permissionDenied }
        try Task.checkCancellation()
        let events = try await recorder.start(experimentID: experimentID, recordingID: recordingID)
        if let header = recorder.activeRecording {
            beginLiveStatus(header)
            if Task.isCancelled { try? await stopAndQueue(header) }
        }
        try Task.checkCancellation()
        return events
    }

    func activate() {
        connectivity.activate()
        observeIncomingReceipts()
        guard startupRecovery == nil else { return }
        startupRecovery = Task {
            do { try await recorder.recoverInterruptedRecordings() } catch {
                // Outbox recovery still checks the readable recordings.
            }
            transfer.startRecovery()
        }
    }

    func events() -> AsyncStream<WatchAudioDeliveryEvent> { transfer.events() }

    func pendingRecording(in experimentID: UUID) async throws -> WatchAudioHeader? {
        activate()
        await startupRecovery?.value
        let headers = try await archive.headers().sorted { $0.startedAt > $1.startedAt }
        for header in headers where header.experimentID == experimentID {
            guard header != recorder.activeRecording, !transfer.isCancellationPending(header)
            else { continue }
            let local = try await archive.statusIfPresent(header)
            let remote = try await archive.remoteReceipt(header)
            guard !local.isCancelled, local.savedRecordID == nil,
                  !local.receivedSequences.isEmpty else { continue }
            if let remote, remote.isSavedAcknowledgement || remote.isCancelled {
                do {
                    try await transfer.receive(remote)
                    continue
                } catch WatchAudioError.conflict {
                    // Reopen the recording so a verified reply can be fetched.
                }
            }
            return header
        }
        return nil
    }

    func deliveryState(
        for header: WatchAudioHeader
    ) async throws -> (isConfirming: Bool, receipt: WatchAudioReceipt?) {
        let receipt = try await archive.remoteReceipt(header)
        if let receipt { try await transfer.receive(receipt) }
        return (await transfer.hasPendingConfirmation(header), receipt)
    }

    func stopAndQueue(_ header: WatchAudioHeader) async throws {
        if recorder.activeRecording == header { await recorder.stop() }
        do {
            let receipt = try await archive.statusIfPresent(header)
            guard !receipt.receivedSequences.isEmpty else { throw WatchAudioError.invalidAudio }
            if receipt.manifest == nil { _ = try await archive.sealInterrupted(header) }
            endLiveStatus(header, phase: .previewing)
        } catch {
            let local = try? await archive.statusIfPresent(header)
            endLiveStatus(
                header, phase: local?.receivedSequences.isEmpty == false ? .previewing : .failed
            )
            if (error as? WatchAudioError) == .invalidAudio,
               local?.receivedSequences.isEmpty == false { throw WatchAudioError.incomplete }
            throw error
        }
        retryDelivery()
    }

    func dismiss(recordingID: UUID) {
        Task {
            if let header = recorder.activeRecording ?? liveHeader,
               header.recordingID == recordingID {
                try? await stopAndQueue(header)
            }
        }
    }

    func retryDelivery() {
        activate()
        Task { await transfer.recover() }
    }

    func confirm(_ header: WatchAudioHeader) async throws {
        try await transfer.requestConfirmation(header)
        retryDelivery()
    }

    func cancelInBackground(_ header: WatchAudioHeader?, recordingID: UUID) {
        let target = header ?? recorder.activeRecording.flatMap {
            $0.recordingID == recordingID ? $0 : nil
        }
        if let target { transfer.prepareCancellation(target) }
        Task {
            if recorder.activeRecording == target, target != nil { await recorder.stop() }
            guard let target else { return }
            endLiveStatus(target, phase: .previewing)
            transfer.releaseCancellation(target)
            await transfer.recover()
        }
    }

    func requireSettledRecordings(in experimentID: UUID) async throws {
        activate()
        await startupRecovery?.value
        guard recorder.activeRecording?.experimentID != experimentID,
              !recorder.isStarting else { throw WatchExperimentError.phoneBusy }
        for header in try await archive.headers() where header.experimentID == experimentID {
            let local = try await archive.statusIfPresent(header)
            let remote = try await archive.remoteReceipt(header)
            if let remote, remote.isSavedAcknowledgement || remote.isCancelled {
                try await transfer.receive(remote)
                continue
            }
            if transfer.isCancellationPending(header) { throw WatchExperimentError.phoneBusy }
            guard !local.isCancelled, local.savedRecordID == nil else { continue }
            if !local.receivedSequences.isEmpty || local.manifest != nil {
                throw WatchExperimentError.phoneBusy
            }
        }
    }

    private func beginLiveStatus(_ header: WatchAudioHeader) {
        liveStatusTask?.cancel()
        liveHeader = header
        liveStatusTask = Task {
            while !Task.isCancelled {
                guard recorder.activeRecording == header else {
                    try? await stopAndQueue(header)
                    return
                }
                sendLiveStatus(header, phase: .recording)
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    private func endLiveStatus(
        _ header: WatchAudioHeader, phase: WatchRecordSnapshot.Phase
    ) {
        guard liveHeader == header else { return }
        liveStatusTask?.cancel()
        liveStatusTask = nil
        liveHeader = nil
        sendLiveStatus(header, phase: phase)
    }

    private func sendLiveStatus(
        _ header: WatchAudioHeader, phase: WatchRecordSnapshot.Phase
    ) {
        guard let session = connectivity.session,
              session.activationState == .activated,
              let data = try? JSONEncoder().encode(WatchVoiceLiveStatus(
                experimentID: header.experimentID, recordingID: header.recordingID,
                startedAt: header.startedAt, sentAt: .now,
                isRecording: phase == .recording, phase: phase,
                elapsedSeconds: max(0, Date.now.timeIntervalSince(header.startedAt))
              )) else { return }
        guard session.isReachable else { return }
        session.sendMessage(
            [WatchVoiceLiveStatus.messageKey: data],
            replyHandler: { _ in }, errorHandler: { _ in }
        )
    }

    private func observeIncomingReceipts() {
        guard incomingReceipts == nil else { return }
        let receipts = connectivity.audioReceipts()
        incomingReceipts = Task {
            for await receipt in receipts {
                try? await transfer.receive(receipt)
            }
        }
    }

    private func microphonePermission() async -> Bool {
        if AVAudioApplication.shared.recordPermission == .granted { return true }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
