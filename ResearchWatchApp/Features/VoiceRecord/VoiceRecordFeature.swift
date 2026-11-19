import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

@Reducer
struct VoiceRecordFeature {
    enum Phase: Equatable {
        case starting, recording, awaitingTransfer, transcribing, transcript, saving, saved, failed
    }

    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var phase: Phase = .starting
        var recordingID = UUID()
        var header: WatchAudioHeader?
        var isVoiceDetected = false
        var isVoiceReleasePending = false
        var transcript = ""
        var errorMessage: String?
        var deliveryNotice: String?
        var receivedChunkCount = 0
        var latestReceipt: WatchAudioReceipt?
        var isConfirming = false
        var autoSaveSeconds = 3
        var isPresented = false
        var shouldDismiss = false
    }

    enum Action {
        case appeared, disappeared, dismissTapped, finishTapped, retryTapped, rerecordTapped
        case saveTapped, cancelTapped, autoSaveTick(UUID), deliveryDelayed(Phase)
        case started(WatchAudioHeader)
        case resume(WatchAudioHeader)
        case captureEvent(UUID, WatchAudioCaptureEvent)
        case voiceSilenceElapsed
        case delivery(WatchAudioDeliveryEvent)
        case prepared(UUID, confirming: Bool, WatchAudioReceipt?)
        case failed(UUID, WatchAudioError)
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case capture, delivery, prepare, voiceRelease, autoSave
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                guard !state.isPresented, !state.shouldDismiss else { return .none }
                state.isPresented = true
                let experimentID = state.experimentID
                let recordingID = state.recordingID
                return .merge(
                    observeDelivery(),
                    .run { send in
                        do {
                            if let header = try await WatchVoiceRecordingService.shared
                                .pendingRecording(in: experimentID) {
                                await send(.resume(header))
                            } else {
                                try await Self.capture(experimentID, recordingID, send: send)
                            }
                        } catch is CancellationError {
                            return
                        } catch {
                            await send(.failed(recordingID, Self.audioError(error)))
                        }
                    }
                    .cancellable(id: CancelID.capture, cancelInFlight: true)
                )

            case let .resume(header):
                guard state.isPresented, state.phase == .starting else { return .none }
                state.recordingID = header.recordingID
                state.header = header
                return prepareDelivery(state: &state)

            case let .started(header):
                guard state.isPresented, state.phase == .starting,
                      state.recordingID == header.recordingID else { return .none }
                state.header = header
                state.phase = .recording
                return .none

            case let .captureEvent(id, event):
                guard state.isPresented, state.recordingID == id else { return .none }
                switch event {
                case let .recording(header):
                    return .send(.started(header))
                case let .levels(levels):
                    return updateLevels(levels, state: &state)
                case .retaining:
                    return .none
                case .retained, .failed:
                    guard state.phase == .recording else { return .none }
                    return prepareDelivery(state: &state)
                }

            case .voiceSilenceElapsed:
                guard state.phase == .recording, state.isVoiceReleasePending else { return .none }
                state.isVoiceDetected = false
                state.isVoiceReleasePending = false
                return .none

            case .finishTapped:
                guard state.isPresented, state.phase == .recording else { return .none }
                return prepareDelivery(state: &state)

            case let .prepared(id, confirming, receipt):
                guard state.isPresented, state.recordingID == id, state.phase != .saved else {
                    return .none
                }
                if confirming {
                    state.isConfirming = true
                    if state.phase != .failed { state.phase = .saving }
                }
                guard let receipt else { return .none }
                return handleReceipt(receipt, state: &state)

            case let .delivery(event):
                guard state.isPresented, state.phase != .saved else { return .none }
                switch event {
                case let .receipt(receipt):
                    return handleReceipt(receipt, state: &state)
                case let .failed(header, error):
                    guard state.header == header, state.phase != .recording,
                          state.phase != .transcript else { return .none }
                    state.deliveryNotice = error == .permissionDenied
                        ? Self.message(for: .permissionDenied)
                        : "iPhone 연결을 확인하고 다시 시도해 주세요."
                    return .none
                }

            case let .deliveryDelayed(phase):
                guard state.isPresented, state.phase == phase, state.deliveryNotice == nil else {
                    return .none
                }
                state.deliveryNotice = "처리가 지연되고 있어요."
                return .none

            case let .autoSaveTick(recordingID):
                guard state.isPresented, state.phase == .transcript,
                      state.recordingID == recordingID else { return .none }
                state.autoSaveSeconds -= 1
                if state.autoSaveSeconds == 0 { return .send(.saveTapped) }
                return .none

            case .saveTapped:
                guard state.isPresented, state.phase == .transcript,
                      let header = state.header else { return .none }
                return confirm(header, state: &state)

            case .rerecordTapped:
                guard state.isPresented, state.phase == .transcript,
                      let header = state.header else { return .none }
                WatchVoiceRecordingService.shared.cancelInBackground(
                    header, recordingID: header.recordingID
                )
                return restartCapture(state: &state)

            case .retryTapped:
                guard state.isPresented else { return .none }
                state.deliveryNotice = nil
                if state.isConfirming, let header = state.header {
                    return confirm(header, state: &state)
                }
                if state.phase == .failed {
                    if state.header != nil { return prepareDelivery(state: &state) }
                    return restartCapture(state: &state)
                }
                WatchVoiceRecordingService.shared.retryDelivery()
                return .none

            case let .failed(id, error):
                guard state.isPresented, state.recordingID == id, state.phase != .saved else {
                    return .none
                }
                state.phase = .failed
                state.errorMessage = Self.message(for: error)
                if error == .invalidAudio { state.header = nil }
                return .cancel(id: CancelID.autoSave)

            case .dismissTapped, .cancelTapped, .disappeared:
                guard state.isPresented else { return .none }
                state.isPresented = false
                if case .cancelTapped = action {
                    WatchVoiceRecordingService.shared.cancelInBackground(
                        state.header, recordingID: state.recordingID
                    )
                } else {
                    WatchVoiceRecordingService.shared.dismiss(recordingID: state.recordingID)
                }
                switch action {
                case .disappeared: break
                default: state.shouldDismiss = true
                }
                return .merge(
                    .cancel(id: CancelID.capture),
                    .cancel(id: CancelID.delivery),
                    .cancel(id: CancelID.prepare),
                    .cancel(id: CancelID.voiceRelease),
                    .cancel(id: CancelID.autoSave)
                )
            }
        }
    }
}

private extension VoiceRecordFeature {
    static func capture(_ experimentID: UUID, _ recordingID: UUID, send: Send<Action>)
        async throws {
        let service = WatchVoiceRecordingService.shared
        let stream = try await service.start(experimentID: experimentID, recordingID: recordingID)
        if let header = service.activeRecording, header.recordingID == recordingID {
            send(.started(header))
        }
        for await event in stream { send(.captureEvent(recordingID, event)) }
    }

    func observeDelivery() -> Effect<Action> {
        .run { send in
            for await event in await WatchVoiceRecordingService.shared.events() {
                await send(.delivery(event))
            }
        }
        .cancellable(id: CancelID.delivery, cancelInFlight: true)
    }

    func restartCapture(state: inout State) -> Effect<Action> {
        let experimentID = state.experimentID
        let recordingID = UUID()
        state = State(experimentID: experimentID, recordingID: recordingID, isPresented: true)
        return .merge(
            .cancel(id: CancelID.autoSave),
            .run { send in
                do {
                    try await Self.capture(experimentID, recordingID, send: send)
                } catch is CancellationError {
                    return
                } catch {
                    await send(.failed(recordingID, Self.audioError(error)))
                }
            }
            .cancellable(id: CancelID.capture, cancelInFlight: true)
        )
    }

    func updateLevels(_ levels: [Float], state: inout State) -> Effect<Action> {
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
    }

    func confirm(_ header: WatchAudioHeader, state: inout State) -> Effect<Action> {
        state.phase = .saving
        state.isConfirming = true
        return .merge(
            .cancel(id: CancelID.autoSave),
            .run { send in
                do {
                    try await WatchVoiceRecordingService.shared.confirm(header)
                } catch is CancellationError {
                    return
                } catch {
                    await send(.failed(header.recordingID, Self.audioError(error)))
                }
            }
        )
    }

    func prepareDelivery(state: inout State) -> Effect<Action> {
        guard let header = state.header else { return .none }
        state.phase = state.isConfirming ? .saving : .awaitingTransfer
        state.isVoiceDetected = false
        state.isVoiceReleasePending = false
        state.errorMessage = nil
        return .merge(
            .cancel(id: CancelID.voiceRelease),
            .run { send in
                do {
                    let service = await WatchVoiceRecordingService.shared
                    try await service.stopAndQueue(header)
                    let delivery = try await service.deliveryState(for: header)
                    await send(.prepared(header.recordingID, confirming: delivery.isConfirming,
                                         delivery.receipt))
                } catch is CancellationError {
                    return
                } catch {
                    await send(.failed(header.recordingID, Self.audioError(error)))
                }
            }
            .cancellable(id: CancelID.prepare, cancelInFlight: true)
        )
    }

    func handleReceipt(_ receipt: WatchAudioReceipt, state: inout State) -> Effect<Action> {
        guard state.header == receipt.header, state.phase != .recording,
              state.phase != .starting else { return .none }
        if let previous = state.latestReceipt, !receipt.canReplace(previous) { return .none }
        state.latestReceipt = receipt
        if receipt.isSavedAcknowledgement {
            state.phase = .saved
            state.deliveryNotice = nil
            return .cancel(id: CancelID.autoSave)
        }
        if receipt.isCancelled {
            state.shouldDismiss = true
            return .cancel(id: CancelID.autoSave)
        }
        if let failure = receipt.failure {
            state.phase = .failed
            state.errorMessage = Self.message(for: failure)
            return .cancel(id: CancelID.autoSave)
        }
        updateProgress(receipt.receivedSequences.count, state: &state)
        if state.isConfirming {
            state.phase = .saving
            return .none
        }
        if state.phase == .awaitingTransfer || state.phase == .failed,
           let manifest = receipt.manifest,
           receipt.receivedSequences.elementsEqual(0..<manifest.chunkCount) {
            state.phase = .transcribing
        }
        guard receipt.isReviewing, let transcript = receipt.transcript, transcript.isFinal else {
            return .none
        }
        state.transcript = transcript.text
        guard state.phase != .transcript else { return .none }
        state.phase = .transcript
        state.deliveryNotice = nil
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

    func updateProgress(_ count: Int, state: inout State) {
        guard count > state.receivedChunkCount else { return }
        state.receivedChunkCount = count
        state.deliveryNotice = nil
    }

    static func audioError(_ error: Error) -> WatchAudioError {
        (error as? WatchAudioError) ?? .interrupted
    }

    static func message(for error: WatchAudioError) -> String {
        switch error {
        case .permissionDenied: "Watch 마이크와 iPhone 음성 인식 권한을 확인해 주세요."
        case .invalidAudio: "녹음된 음성이 없어요. 다시 시도해 주세요."
        case .recognitionUnavailable: "iPhone에서 전사하지 못했어요. 다시 시도해 주세요."
        case .storageFull, .storageFailed: "음성 저장에 실패했어요. 저장 공간을 확인해 주세요."
        default: "음성 기록을 진행할 수 없어요. 다시 시도해 주세요."
        }
    }
}
