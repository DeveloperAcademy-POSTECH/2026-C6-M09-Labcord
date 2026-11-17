import AVFoundation
import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS
import WatchConnectivity

@Reducer
struct VoiceRecordFeature {
    enum Phase: Equatable {
        case starting, recording, transcribing, transcript, saving, saved, failed
    }

    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var phase: Phase = .starting
        var header: WatchAudioHeader?
        var isVoiceDetected = false
        var isVoiceReleasePending = false
        var transcript = ""
        var errorMessage: String?
        var hasRetainedAudio = false
        var autoSaveSeconds = 3
        var isClosing = false
        var shouldDismiss = false
    }

    enum Action {
        case appeared, disappeared, finishTapped, retryTapped, rerecordTapped
        case saveTapped, cancelTapped, cancelQueued, autoSaveTick(UUID)
        case started(WatchAudioHeader)
        case captureEvent(WatchAudioCaptureEvent)
        case voiceSilenceElapsed
        case receipt(WatchAudioReceipt)
        case stopped(WatchAudioHeader)
        case failed(String)
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case capture, receipts, voiceRelease, autoSave
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                guard !state.isClosing else { return .none }
                let experimentID = state.experimentID
                return .merge(
                    .run { send in
                        do {
                            let stream = try await WatchVoiceRecordingService.shared.start(
                                experimentID: experimentID
                            )
                            let header = await WatchVoiceRecordingService.shared.activeRecording
                            if let header {
                                await send(.started(header))
                            }
                            for await event in stream { await send(.captureEvent(event)) }
                        } catch {
                            await send(.failed(Self.message(for: error)))
                        }
                    }
                    .cancellable(id: CancelID.capture, cancelInFlight: true),
                    .run { send in
                        for await receipt in await WatchVoiceRecordingService.shared.receipts() {
                            await send(.receipt(receipt))
                        }
                    }
                    .cancellable(id: CancelID.receipts, cancelInFlight: true)
                )

            case let .started(header):
                guard !state.isClosing, state.phase == .starting else { return .none }
                state.header = header
                state.phase = .recording
                return .none

            case let .captureEvent(event):
                guard !state.isClosing else { return .none }
                switch event {
                case let .recording(header):
                    if state.phase == .starting {
                        state.header = header
                        state.phase = .recording
                    }
                case let .levels(levels):
                    guard state.phase == .recording else { return .none }
                    if levels.contains(where: { $0 > 0.05 }) {
                        state.isVoiceDetected = true
                        state.isVoiceReleasePending = false
                        return .cancel(id: CancelID.voiceRelease)
                    }
                    guard state.isVoiceDetected, !state.isVoiceReleasePending else { return .none }
                    state.isVoiceReleasePending = true
                    return .run { send in
                        try await Task.sleep(for: .milliseconds(350))
                        await send(.voiceSilenceElapsed)
                    }
                    .cancellable(id: CancelID.voiceRelease)
                case .retaining, .retained:
                    break
                case let .failed(error):
                    state.phase = .failed
                    state.errorMessage = Self.message(for: error)
                    state.isVoiceDetected = false
                    state.isVoiceReleasePending = false
                    return .merge(
                        .cancel(id: CancelID.voiceRelease),
                        .run { _ in
                            await WatchVoiceRecordingService.shared.stopAndQueueIfNeeded()
                        }
                    )
                }
                return .none

            case .voiceSilenceElapsed:
                guard state.phase == .recording, state.isVoiceReleasePending else { return .none }
                state.isVoiceDetected = false
                state.isVoiceReleasePending = false
                return .none

            case .finishTapped:
                guard state.phase == .recording, !state.isClosing else { return .none }
                state.phase = .transcribing
                state.isVoiceDetected = false
                state.isVoiceReleasePending = false
                return .merge(
                    .cancel(id: CancelID.voiceRelease),
                    .run { send in
                        do {
                            let header = try await WatchVoiceRecordingService.shared.stopAndQueue()
                            await send(.stopped(header))
                        } catch {
                            await send(.failed(Self.message(for: error)))
                        }
                    }
                )

            case let .stopped(header):
                guard !state.isClosing, state.phase == .transcribing else { return .none }
                state.header = header
                state.hasRetainedAudio = true
                return .none

            case let .receipt(receipt):
                guard !state.isClosing else { return .none }
                guard receipt.header.experimentID == state.experimentID,
                      receipt.header.recordingID == state.header?.recordingID else { return .none }
                if receipt.savedRecordID == receipt.header.recordingID {
                    state.phase = .saved
                    state.autoSaveSeconds = 0
                    return .cancel(id: CancelID.autoSave)
                }
                if receipt.isCancelled { return .none }
                if let failure = receipt.failure {
                    state.phase = .failed
                    state.errorMessage = Self.message(for: failure)
                    state.hasRetainedAudio = state.hasRetainedAudio
                        || !receipt.receivedSequences.isEmpty
                    return .cancel(id: CancelID.autoSave)
                }
                if let transcript = receipt.transcript, transcript.isFinal {
                    state.transcript = transcript.text
                }
                if receipt.isReviewing, receipt.transcript?.isFinal == true,
                   state.phase == .transcribing {
                    state.phase = .transcript
                    state.autoSaveSeconds = 3
                    let recordingID = receipt.header.recordingID
                    return .run { send in
                        for _ in 0..<3 {
                            try await Task.sleep(for: .seconds(1))
                            await send(.autoSaveTick(recordingID))
                        }
                    }
                    .cancellable(id: CancelID.autoSave, cancelInFlight: true)
                }
                return .none

            case let .autoSaveTick(recordingID):
                guard !state.isClosing, state.phase == .transcript,
                      state.header?.recordingID == recordingID else { return .none }
                state.autoSaveSeconds -= 1
                if state.autoSaveSeconds == 0 { return .send(.saveTapped) }
                return .none

            case .saveTapped:
                guard !state.isClosing, state.phase == .transcript,
                      let header = state.header else { return .none }
                state.phase = .saving
                return .merge(
                    .cancel(id: CancelID.autoSave),
                    .run { _ in await WatchVoiceRecordingService.shared.confirm(header) }
                )

            case .rerecordTapped:
                guard state.phase == .transcript, let header = state.header else { return .none }
                state.phase = .starting
                state.header = nil
                state.transcript = ""
                state.hasRetainedAudio = false
                state.autoSaveSeconds = 3
                state.isVoiceDetected = false
                state.isVoiceReleasePending = false
                let experimentID = state.experimentID
                return .merge(
                    .cancel(id: CancelID.autoSave),
                    .cancel(id: CancelID.capture),
                    .run { send in
                        await WatchVoiceRecordingService.shared.cancel(header)
                        guard !Task.isCancelled else { return }
                        let stream = try? await WatchVoiceRecordingService.shared.start(
                            experimentID: experimentID
                        )
                        guard let stream else {
                            await send(.failed("녹음을 다시 시작할 수 없어요."))
                            return
                        }
                        if let active = await WatchVoiceRecordingService.shared.activeRecording {
                            await send(.started(active))
                        }
                        for await event in stream { await send(.captureEvent(event)) }
                    }
                    .cancellable(id: CancelID.capture, cancelInFlight: true)
                )

            case .cancelTapped:
                guard state.phase != .saved, !state.isClosing else { return .none }
                state.isClosing = true
                let header = state.header
                return .merge(
                    .cancel(id: CancelID.capture),
                    .cancel(id: CancelID.receipts),
                    .cancel(id: CancelID.voiceRelease),
                    .cancel(id: CancelID.autoSave),
                    .run { send in
                        await WatchVoiceRecordingService.shared.cancelInBackground(header)
                        await send(.cancelQueued)
                    }
                )

            case .cancelQueued:
                guard state.isClosing else { return .none }
                state.shouldDismiss = true
                return .none

            case .retryTapped:
                guard state.phase == .failed else { return .none }
                if state.hasRetainedAudio {
                    state.phase = .transcribing
                    state.errorMessage = nil
                    let header = state.header
                    return .run { _ in
                        await WatchVoiceRecordingService.shared.retryDelivery(for: header)
                    }
                }
                state.phase = .starting
                state.errorMessage = nil
                state.header = nil
                state.hasRetainedAudio = false
                state.isVoiceDetected = false
                state.isVoiceReleasePending = false
                return .send(.appeared)

            case let .failed(message):
                guard !state.isClosing else { return .none }
                state.phase = .failed
                state.errorMessage = message
                state.isVoiceDetected = false
                state.isVoiceReleasePending = false
                return .cancel(id: CancelID.voiceRelease)

            case .disappeared:
                let shouldCancel = state.phase != .saved && !state.isClosing
                let header = state.header
                return .merge(
                    .cancel(id: CancelID.capture),
                    .cancel(id: CancelID.receipts),
                    .cancel(id: CancelID.voiceRelease),
                    .cancel(id: CancelID.autoSave),
                    shouldCancel ? .run { _ in
                        await WatchVoiceRecordingService.shared.cancelInBackground(header)
                    } : .none
                )
            }
        }
    }

    private static func message(for error: Error) -> String {
        switch error as? WatchAudioError {
        case .permissionDenied:
            "Watch 마이크와 iPhone 음성 인식 권한을 확인해 주세요."
        case .invalidAudio: "녹음된 음성이 없어요. 다시 시도해 주세요."
        case .recognitionUnavailable: "iPhone에서 음성을 전사할 수 없어요."
        default: "음성 기록을 진행할 수 없어요. 다시 시도해 주세요."
        }
    }
}

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

    func retryDelivery(for header: WatchAudioHeader?) async {
        if let header, requestedConfirmations.remove(header.recordingID) != nil {
            await confirm(header)
        }
        await transfer.recover()
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
