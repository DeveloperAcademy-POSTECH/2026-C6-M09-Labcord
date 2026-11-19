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
    private var confirmationQueue: Task<Void, Never>?
    private var liveStatusTask: Task<Void, Never>?
    private var liveHeader: WatchAudioHeader?
    private let pendingKey = "Labcord.WatchAudio.pendingConfirmations"
    private var pendingConfirmations: [UUID: WatchAudioHeader] = [:]
    private var requestedConfirmations: Set<UUID> = []

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
        let pending = UserDefaults.standard.data(forKey: pendingKey)
            .flatMap { try? JSONDecoder().decode([WatchAudioHeader].self, from: $0) } ?? []
        pendingConfirmations = Dictionary(
            pending.map { ($0.recordingID, $0) }
        ) { first, _ in first }
        requestedConfirmations = Set(pendingConfirmations.keys)
    }

    func start(experimentID: UUID) async throws -> AsyncStream<WatchAudioCaptureEvent> {
        activate()
        guard await microphonePermission() else { throw WatchAudioError.permissionDenied }
        let events = try await recorder.start(experimentID: experimentID)
        if let header = recorder.activeRecording { beginLiveStatus(header) }
        return events
    }

    func activate() {
        connectivity.activate()
        observeIncomingReceipts()
        transfer.startRecovery()
        flushConfirmations()
    }

    func receipts() -> AsyncStream<WatchAudioReceipt> { transfer.receipts() }

    func stopAndQueue() async throws -> WatchAudioHeader {
        guard let header = recorder.activeRecording else { throw WatchAudioError.invalidAudio }
        await recorder.stop()
        do {
            let receipt = try await archive.statusEnsuringArchive(header)
            guard !receipt.receivedSequences.isEmpty, receipt.manifest != nil else {
                throw WatchAudioError.invalidAudio
            }
        } catch {
            endLiveStatus(header, phase: .failed)
            throw error
        }
        endLiveStatus(header, phase: .previewing)
        Task { await transfer.recover() }
        return header
    }

    func retryDelivery(for header: WatchAudioHeader?) async -> WatchAudioReceipt? {
        if let header, requestedConfirmations.remove(header.recordingID) != nil {
            await confirm(header)
        }
        await transfer.recover()
        guard let header else { return nil }
        return try? await archive.remoteReceipt(header)
    }

    func stopAndQueueIfNeeded() async {
        if recorder.isStarting { _ = await recorder.cancelPendingStart() }
        guard let header = recorder.activeRecording else {
            if let liveHeader { endLiveStatus(liveHeader, phase: .failed) }
            return
        }
        _ = try? await stopAndQueue()
        sendLiveStatus(header, phase: .failed)
    }

    func confirm(_ header: WatchAudioHeader) async {
        guard requestedConfirmations.insert(header.recordingID).inserted else { return }
        pendingConfirmations[header.recordingID] = header
        persistConfirmations()
        flushConfirmations()
    }

    func cancelInBackground(_ header: WatchAudioHeader?) {
        let target = header ?? recorder.activeRecording ?? liveHeader
        if let target {
            transfer.prepareCancellation(target)
            pendingConfirmations.removeValue(forKey: target.recordingID)
            requestedConfirmations.remove(target.recordingID)
            persistConfirmations()
            endLiveStatus(target, phase: .cancelled)
        }
        Task { await cancel(target) }
    }

    func cancel(_ header: WatchAudioHeader?) async {
        if recorder.isStarting { _ = await recorder.cancelPendingStart() }
        let target = header ?? recorder.activeRecording
        if let target {
            transfer.prepareCancellation(target)
            pendingConfirmations.removeValue(forKey: target.recordingID)
            requestedConfirmations.remove(target.recordingID)
            persistConfirmations()
            endLiveStatus(target, phase: .cancelled)
        }
        if recorder.activeRecording != nil { await recorder.stop() }
        guard let target else { return }
        transfer.releaseCancellation(target)
        do { _ = try await transfer.cancel(target) } catch { await transfer.recover() }
    }

    private func flushConfirmations() {
        guard confirmationQueue == nil, !pendingConfirmations.isEmpty else { return }
        confirmationQueue = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, !pendingConfirmations.isEmpty {
                connectivity.activate()
                if connectivity.session?.activationState == .activated {
                    for header in Array(pendingConfirmations.values) {
                        guard pendingConfirmations[header.recordingID] != nil,
                              !transfer.isCancellationPending(header) else { continue }
                        guard let data = try? JSONEncoder().encode(
                            WatchAudioMessage.confirm(header)
                        ) else { continue }
                        connectivity.transferUserInfo(["labcordAudioMessage": data])
                        pendingConfirmations.removeValue(forKey: header.recordingID)
                    }
                    persistConfirmations()
                } else {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            confirmationQueue = nil
        }
    }

    private func beginLiveStatus(_ header: WatchAudioHeader) {
        liveStatusTask?.cancel()
        liveHeader = header
        liveStatusTask = Task {
            while !Task.isCancelled {
                sendLiveStatus(header, phase: .recording)
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    private func endLiveStatus(
        _ header: WatchAudioHeader, phase: WatchRecordSnapshot.Phase
    ) {
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
        if phase == .cancelled {
            connectivity.transferUserInfo([WatchVoiceLiveStatus.messageKey: data])
        }
        guard session.isReachable else { return }
        session.sendMessage(
            [WatchVoiceLiveStatus.messageKey: data],
            replyHandler: { _ in }, errorHandler: { _ in }
        )
    }

    private func persistConfirmations() {
        let values = Array(pendingConfirmations.values)
        UserDefaults.standard.set(try? JSONEncoder().encode(values), forKey: pendingKey)
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
