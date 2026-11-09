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

            case .watchResourcesReleased:
                guard let command = state.watchCommand else { return .none }
                if command.operation == .complete {
                    return .send(.pause(.completeRequested))
                }
                state.timer.isClosing = false
                return .send(.pause(.delegate(.returnHomeRequested)))

            case .watchControlFinished:
                state.watchCommand = nil
                return .none

            default:
                return .none
            }
        }
    }

    func prepareWatchClose(
        _ command: WatchExperimentCommand, state: inout State
    ) -> Effect<Action> {
        guard state.watchCommand == nil, state.canCloseSession,
              state.voice.phase == .hidden, state.capture.videoPhase == .idle,
              !state.capture.isCapturingPhoto, state.capture.capturedPhotoData == nil,
              !state.capture.photo.isSaving else {
            return .send(.watchControlFinished(command.requestID, .phoneBusy))
        }
        guard command.operation == .pause || command.operation == .complete else {
            return .send(.watchControlFinished(command.requestID, .invalidState))
        }
        state.watchCommand = command
        state.timer.isClosing = true
        state.watchCameraWasVisible = state.capture.isCameraViewVisible
        let ownerID = state.capture.camera.ownerID
        return .concatenate(
            .send(.capture(.cancelPhotoGesture)),
            .send(.voice(.closeRequested)),
            .send(.capture(.cameraViewDisappeared)),
            .run { send in
                await cameraSessionClient.cancelVideoRecording()
                await speechRecordingClient.cancel()
                await cameraSessionClient.deactivate(ownerID)
                await send(.watchResourcesReleased)
            }
        )
    }

    func finishWatchClose(
        state: inout State, error: WatchExperimentError?
    ) -> Effect<Action> {
        guard let command = state.watchCommand else { return .none }
        state.watchCommand = nil
        let finished = Effect<Action>.send(.watchControlFinished(command.requestID, error))
        guard state.watchCameraWasVisible else { return finished }
        state.watchCameraWasVisible = false
        return .concatenate(
            finished,
            .send(.capture(.cameraViewAppeared)),
            .send(.capture(.cameraActivationRequested))
        )
    }

}
