import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

extension ExperimentSessionFeature {
    var watchReducer: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .watchControl(command):
                return prepareWatchClose(command, state: &state)

            case let .watchRecordControl(command):
                return handleWatchRecord(command, state: &state)

            case .watchDrainProgress:
                return drainWatchClose(state: &state)

            case let .capture(.video(.watchPauseDiscarded(id))):
                guard state.watchCommand?.operation == .pause,
                      state.capture.video.isDiscardingForWatchPause,
                      state.capture.video.sessionID == id else { return .none }
                return .send(.watchDrainProgress)

            case let .voice(.watchPauseDiscarded(id)):
                guard state.watchCommand?.operation == .pause,
                      state.voice.isPauseCancellationPending,
                      state.voice.sessionID == id else { return .none }
                return .send(.watchDrainProgress)

            case .watchResourcesReleased:
                guard let command = state.watchCommand, state.watchClosingResources else {
                    return .none
                }
                return .send(command.operation == .complete ? .stopTapped : .returnHomeTapped)

            case let .watchControlFinished(id, _):
                guard state.watchCommand?.requestID == id else { return .none }
                state.watchCommand = nil
                state.watchClosingResources = false
                return .none

            default:
                return .none
            }
        }
    }

    func prepareWatchClose(
        _ command: WatchExperimentCommand, state: inout State
    ) -> Effect<Action> {
        guard command.experimentID == state.experimentID,
              command.operation == .pause || command.operation == .complete else {
            return .send(.watchControlFinished(command.requestID, .invalidState))
        }
        guard state.watchCommand == nil, state.watchMediaCommand == nil, state.timer.isConfigured,
              !state.isCompleting, !state.isReturningHome,
              state.timer.pendingSave == nil || state.timer.isSaving else {
            return .send(.watchControlFinished(command.requestID, .phoneBusy))
        }
        state.watchCommand = command
        setWatchDrainOwnership(true, state: &state)
        state.timer.isClosing = true
        state.watchClosingResources = false
        state.watchCameraWasVisible = state.capture.isCameraViewVisible
        return .concatenate(
            .send(.capture(.cancelPhotoGesture)),
            .send(.watchDrainProgress)
        )
    }

    func drainWatchClose(state: inout State) -> Effect<Action> {
        guard state.watchCommand != nil, !state.watchClosingResources else { return .none }
        var effects: [Effect<Action>] = []
        if state.voice.phase != .hidden, !state.voice.isSaving {
            effects.append(watchVoiceCloseEffect(state: state))
        }
        if state.capture.videoPhase != .idle, !state.capture.video.isSaving {
            effects.append(.send(.capture(.video(.stopAndSaveRequested))))
        }
        if state.capture.capturedPhotoData != nil, !state.capture.photo.isSaving {
            effects.append(.send(.capture(.photo(.saveRequested))))
        }
        guard state.voice.phase == .hidden, !state.voice.isSaving,
              state.capture.videoPhase == .idle, !state.capture.video.isSaving,
              !state.capture.isCapturingPhoto, state.capture.capturedPhotoData == nil,
              !state.capture.photo.isSaving, state.timer.pendingSave == nil else {
            return .merge(effects)
        }
        state.watchClosingResources = true
        let ownerID = state.capture.camera.ownerID
        return .concatenate(
            .send(.capture(.cameraViewDisappeared)),
            .run { send in
                await cameraSessionClient.cancelVideoRecording()
                await speechRecordingClient.cancel()
                await cameraSessionClient.deactivate(ownerID)
                await send(.watchResourcesReleased)
            }
        )
    }

    private func watchVoiceCloseEffect(state: State) -> Effect<Action> {
        .send(.voice(.stopAndSaveRequested))
    }

    private func setWatchDrainOwnership(_ closing: Bool, state: inout State) {
        state.voice.isSessionClosing = closing
        state.capture.photo.isSessionClosing = closing
        state.capture.video.isSessionClosing = closing
    }

    func finishWatchClose(
        state: inout State, error: WatchExperimentError?
    ) -> Effect<Action> {
        guard let command = state.watchCommand else { return .none }
        let restoreCamera = state.watchCameraWasVisible && state.watchClosingResources
        state.watchCommand = nil
        setWatchDrainOwnership(false, state: &state)
        state.watchClosingResources = false
        state.watchCameraWasVisible = false
        let finished = Effect<Action>.send(.watchControlFinished(command.requestID, error))
        guard restoreCamera else { return finished }
        return .concatenate(
            finished,
            .send(.capture(.cameraViewAppeared)),
            .send(.capture(.cameraActivationRequested))
        )
    }
}
