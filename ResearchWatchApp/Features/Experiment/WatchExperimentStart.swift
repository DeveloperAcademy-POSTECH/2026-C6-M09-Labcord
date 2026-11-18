import ComposableArchitecture
import Foundation
import LabcordShared

extension WatchExperimentFeature {
    func reduceStart(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .permissionRequested:
            guard state.screen == .permission, !state.isRequestingPermission,
                  let id = state.selectedID else { return .none }
            state.isRequestingPermission = true
            let requestID = uuid()
            state.permissionRequestID = requestID
            return .run { [microphonePermission] send in
                let granted = await microphonePermission.request()
                guard !Task.isCancelled else { return }
                await send(.permissionResult(id, requestID, granted))
            }
            .cancellable(id: CancelID.permission, cancelInFlight: true)
        case let .permissionResult(id, requestID, granted):
            guard state.isVisible, state.selectedID == id, state.screen == .permission,
                  state.permissionRequestID == requestID, state.isRequestingPermission,
                  state.snapshot?.experiment.status == .ready else {
                return .none
            }
            state.isRequestingPermission = false
            state.permissionRequestID = nil
            state.permissionDenied = !granted
            guard granted else { return .none }
            let endsAt = now.addingTimeInterval(3)
            state.localCountdownEndsAt = endsAt
            return navigateToStage(.countdown, countdownEndsAt: endsAt, state: &state)
        default:
            return .none
        }
    }
}
