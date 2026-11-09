import ComposableArchitecture
import Foundation

extension WatchExperimentFeature {
    func reduceStart(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .permissionRequested:
            guard state.screen == .permission, !state.isRequestingPermission,
                  let id = state.selectedID else { return .none }
            state.isRequestingPermission = true
            return .run { [microphonePermission] send in
                let granted = await microphonePermission.request()
                guard !Task.isCancelled else { return }
                await send(.permissionResult(id, granted))
            }
            .cancellable(id: CancelID.permission, cancelInFlight: true)
        case let .permissionResult(id, granted):
            guard state.isVisible, state.selectedID == id, state.screen == .permission else {
                return .none
            }
            state.isRequestingPermission = false
            state.permissionDenied = !granted
            guard granted else { return .none }
            let countdownID = uuid()
            state.countdownID = countdownID
            state.screen = .countdown(3)
            return countdown(token: countdownID)
        default:
            return .none
        }
    }
}
