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

            case let .watchDrainProgress(requestID):
                guard state.watchCommand?.requestID == requestID else { return .none }
                return drainWatchClose(state: &state)

            case let .watchResourcesReleased(requestID):
                guard let command = state.watchCommand, command.requestID == requestID,
                      state.watchClosingResources else { return .none }
                if command.operation == .complete {
                    return .send(.pause(.completeRequested(command.requestID)))
                }
                state.timer.isClosing = false
                return .send(.pause(.delegate(.returnHomeRequested)))

            case let .watchControlFinished(id, _):
                guard state.watchCommand?.requestID == id else { return .none }
                clearWatchDrain(state: &state)
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
        guard state.watchCommand == nil, state.watchMediaCommand == nil,
              state.timer.isConfigured, state.timer.pendingSave == nil, !state.timer.isClosing,
              !state.timer.hasUnsavedDraft,
              !state.pause.isCompleting, !state.isReturningHome,
              !state.voice.hasRecordingFailure,
              WatchDrainGate.canDrainVoice(
                isStarting: state.voice.phase == .starting,
                captureStartRequested: state.voice.captureStartRequested
              ) else {
            return .send(.watchControlFinished(command.requestID, .phoneBusy))
        }
        let photo = state.capture.photo
        let photoNeedsSave = photo.isCapturing || photo.capturedData != nil || photo.isSaving
        guard !photoNeedsSave || photo.requestedRecordID != nil || photo.recordID != nil,
              !state.voice.isSaving || state.voice.phase != .hidden,
              !state.capture.video.isSaving || state.capture.videoPhase != .idle else {
            return .send(.watchControlFinished(command.requestID, .storageFailed))
        }
        state.watchCommand = command
        state.watchClosingResources = false
        state.watchDrainGate = WatchDrainGate(
            voiceSession: state.voice.phase == .hidden ? nil : state.voice.sessionID,
            voiceRecord: state.voice.recordID,
            videoSession: state.capture.videoPhase == .idle ? nil : state.capture.video.sessionID,
            videoRecord: state.capture.video.recordID,
            photoRecord: photoNeedsSave ? photo.requestedRecordID ?? photo.recordID : nil
        )
        state.watchCameraWasVisible = state.capture.isCameraViewVisible
        state.voice.isSessionClosing = true
        state.capture.photo.isSessionClosing = true
        state.capture.video.isSessionClosing = true
        state.timer.isClosing = true
        return .concatenate(
            .send(.capture(.cancelPhotoGesture)),
            .send(.watchDrainProgress(command.requestID))
        )
    }

    func drainWatchClose(state: inout State) -> Effect<Action> {
        guard let command = state.watchCommand, let gate = state.watchDrainGate,
              !state.watchClosingResources else { return .none }
        if gate.voiceSession != nil, state.voice.phase == .finished,
           !state.voice.isSaving,
           state.voice.recording == nil || state.voice.recordID == nil
            || state.voice.recordedAt == nil {
            return failWatchDrain(state: &state)
        }
        if gate.videoSession != nil, case .preview = state.capture.video.phase,
           !state.capture.video.isSaving,
           state.capture.video.recordID == nil || state.capture.video.recordedAt == nil {
            return failWatchDrain(state: &state)
        }
        var effects: [Effect<Action>] = []
        if gate.voiceSession != nil, !state.voice.isSaving {
            effects.append(.send(.voice(.stopAndSaveRequested)))
        }
        if gate.videoSession != nil, !state.capture.video.isSaving {
            effects.append(.send(.capture(.video(.stopAndSaveRequested))))
        }
        if gate.photoRecord != nil, state.capture.photo.capturedData != nil,
           !state.capture.photo.isSaving {
            effects.append(.send(.capture(.photo(.saveRequested))))
        }
        guard gate.voiceSession == nil, gate.videoSession == nil,
              gate.photoRecord == nil else { return .merge(effects) }
        state.watchClosingResources = true
        let ownerID = state.capture.camera.ownerID
        return .concatenate(
            .send(.capture(.cameraViewDisappeared)),
            .run { send in
                await cameraSessionClient.cancelVideoRecording()
                await speechRecordingClient.cancel()
                await cameraSessionClient.deactivate(ownerID)
                await send(.watchResourcesReleased(command.requestID))
            }
        )
    }

    func failWatchDrain(state: inout State) -> Effect<Action> {
        guard state.watchCommand != nil else { return .none }
        state.timer.isClosing = false
        return .merge(
            .send(.timer(.timerTick(now))),
            finishWatchClose(state: &state, error: .storageFailed)
        )
    }

    func acceptHomeExit(
        _ attemptID: UUID, requestID: UUID?, state: inout State
    ) -> Effect<Action> {
        guard requestID == state.watchCommand?.requestID,
              state.homeExitAttempt.accept(attemptID) else { return .none }
        clearWatchDrain(state: &state)
        state.watchCameraWasVisible = false
        return .none
    }

    func failHomeExit(
        _ attemptID: UUID, requestID: UUID?, state: inout State
    ) -> Effect<Action> {
        guard requestID == state.watchCommand?.requestID,
              state.homeExitAttempt.accept(attemptID) else { return .none }
        state.isReturningHome = false
        state.timer.isClosing = false
        return .merge(
            .send(.timer(.timerTick(now))),
            .send(.pause(.homeExitFailed)),
            finishWatchClose(state: &state, error: .storageFailed)
        )
    }

    func clearWatchDrain(state: inout State) {
        state.watchCommand = nil
        state.watchClosingResources = false
        state.watchDrainGate = nil
        state.voice.isSessionClosing = false
        state.capture.photo.isSessionClosing = false
        state.capture.video.isSessionClosing = false
    }

    func finishWatchClose(
        state: inout State, error: WatchExperimentError?
    ) -> Effect<Action> {
        guard let command = state.watchCommand else { return .none }
        let restoreCamera = state.watchCameraWasVisible && state.watchClosingResources
        clearWatchDrain(state: &state)
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
