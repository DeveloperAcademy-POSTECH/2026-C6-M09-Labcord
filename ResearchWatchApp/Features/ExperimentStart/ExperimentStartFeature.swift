import ComposableArchitecture
import LabcordShared

enum ExperimentStartPhase: Equatable {
    case details
    case requestingPermission
    case permissionDenied
    case countdown(Int?)
    case experiment
}

@Reducer
struct ExperimentStartFeature {
    @ObservableState
    struct State: Equatable {
        let experiment: WatchExperimentSummary
        var phase: ExperimentStartPhase = .details
    }

    enum Action {
        case startTapped
        case permissionUpdated(PermissionStatus)
        case permissionRecheckTapped
        case countdownTick
        case experimentDismissed
        case becameInactive
        case disappeared
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case permission
        case countdown
    }

    @Dependency(\.microphonePermissionClient) private var microphonePermission

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startTapped:
                guard state.phase == .details else { return .none }
                switch microphonePermission.currentStatus() {
                case .authorized:
                    return beginCountdown(&state)
                case .notDetermined:
                    state.phase = .requestingPermission
                    return .run { send in
                        let status = await microphonePermission.requestAccess()
                        await send(.permissionUpdated(status))
                    }
                    .cancellable(id: CancelID.permission, cancelInFlight: true)
                case .denied, .restricted:
                    state.phase = .permissionDenied
                }
                return .none

            case let .permissionUpdated(status):
                guard state.phase == .requestingPermission else { return .none }
                if status == .authorized { return beginCountdown(&state) }
                state.phase = .permissionDenied
                return .none

            case .permissionRecheckTapped:
                guard state.phase == .permissionDenied else { return .none }
                if microphonePermission.currentStatus() == .authorized {
                    return beginCountdown(&state)
                }
                return .none

            case .countdownTick:
                guard case let .countdown(number) = state.phase else { return .none }
                switch number {
                case nil: state.phase = .countdown(3)
                case 1: state.phase = .experiment
                case let .some(value): state.phase = .countdown(value - 1)
                }
                return .none

            case .experimentDismissed:
                guard state.phase == .experiment else { return .none }
                state.phase = .details
                return .none

            case .becameInactive:
                if case .countdown = state.phase { state.phase = .details }
                return .cancel(id: CancelID.countdown)

            case .disappeared:
                if state.phase != .experiment { state.phase = .details }
                return .merge(
                    .cancel(id: CancelID.permission),
                    .cancel(id: CancelID.countdown)
                )
            }
        }
    }

    private func beginCountdown(_ state: inout State) -> Effect<Action> {
        state.phase = .countdown(nil)
        return .run { send in
            for _ in 0..<4 {
                try await Task.sleep(for: .seconds(1))
                await send(.countdownTick)
            }
        }
        .cancellable(id: CancelID.countdown, cancelInFlight: true)
    }
}
