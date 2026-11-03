import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

extension ExperimentSessionFeature {
    var cameraRecoveryReducer: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .capture(.camera(.startFailed(ownerID, _))):
                guard state.capture.camera.isViewVisible,
                      state.capture.camera.ownerID == ownerID else { return .none }
                state.cameraStartupFailed = true
                return .none

            case let .capture(.camera(.started(ownerID, _))):
                guard state.capture.camera.isViewVisible,
                      state.capture.camera.ownerID == ownerID else { return .none }
                state.cameraStartupFailed = false
                state.allowsAudioOnly = false
                return .none

            case .continueWithoutCamera:
                guard state.canContinueWithoutCamera else { return .none }
                state.allowsAudioOnly = true
                removeOptionalCameraIssue(state: &state)
                return .merge(
                    .send(.capture(.cameraErrorDismissed)),
                    state.permissions.microphoneStatus == .authorized
                        && state.permissions.speechRecognitionStatus == .authorized
                        ? .none : .send(.permissions(.request))
                )

            case .permissions(.requestFinished), .permissions(.issueUpdated):
                if state.allowsAudioOnly { removeOptionalCameraIssue(state: &state) }
                return .none

            case .retryCameraRequested:
                guard !state.permissions.isRequesting, !state.isCompleting,
                      !state.isReturningHome, state.voice.phase == .hidden,
                      state.capture.video.phase == .idle else { return .none }
                state.allowsAudioOnly = false
                state.cameraStartupFailed = false
                return .concatenate(
                    .send(.capture(.cameraErrorDismissed)),
                    .send(.permissions(.request))
                )

            default:
                return .none
            }
        }
    }

    private func removeOptionalCameraIssue(state: inout State) {
        guard case let .accessRequired(requirements) = state.permissions.issue else { return }
        let required = requirements.filter { $0.kind != .camera }
        state.permissions.issue = required.isEmpty ? nil : .accessRequired(required)
    }
}
