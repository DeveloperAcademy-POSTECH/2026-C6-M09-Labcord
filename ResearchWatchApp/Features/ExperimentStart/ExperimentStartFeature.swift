import ComposableArchitecture
import LabcordShared
import LabcordWatchOS

enum ExperimentStartPhase: Equatable {
    case details
    case checkingActiveExperiment
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
        var isActiveExperimentConflictPresented = false
    }

    enum Action {
        case startTapped
        case activeExperimentChecked(hasConflict: Bool)
        case activeExperimentConflictDismissed
        case permissionUpdated(PermissionStatus)
        case permissionRecheckTapped
        case countdownTick
        case becameInactive
        case disappeared
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case activeExperimentCheck
        case permission
        case countdown
        case openSession
    }

    @Dependency(\.microphonePermissionClient) private var microphonePermission
    @Dependency(\.watchExperimentClient) private var watchExperimentClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startTapped:
                guard state.phase == .details,
                      !state.isActiveExperimentConflictPresented else { return .none }
                state.phase = .checkingActiveExperiment
                let experimentID = state.experiment.id
                return .run { send in
                    let experiments = (try? await watchExperimentClient.list()) ?? []
                    let hasConflict = experiments.contains {
                        $0.status == .running && $0.id != experimentID
                    }
                    await send(.activeExperimentChecked(hasConflict: hasConflict))
                }
                .cancellable(id: CancelID.activeExperimentCheck, cancelInFlight: true)

            case let .activeExperimentChecked(hasConflict):
                guard state.phase == .checkingActiveExperiment else { return .none }
                if hasConflict {
                    state.phase = .details
                    state.isActiveExperimentConflictPresented = true
                    return .none
                }
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

            case .activeExperimentConflictDismissed:
                state.isActiveExperimentConflictPresented = false
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

            case .becameInactive:
                if state.phase == .checkingActiveExperiment {
                    state.phase = .details
                    return .cancel(id: CancelID.activeExperimentCheck)
                }
                guard case .countdown = state.phase else {
                    return .cancel(id: CancelID.countdown)
                }
                state.phase = .details
                let experimentID = state.experiment.id
                return .merge(
                    .cancel(id: CancelID.countdown),
                    .cancel(id: CancelID.openSession),
                    .run { _ in await watchExperimentClient.cancelPhoneSession(experimentID) }
                )

            case .disappeared:
                if state.phase == .experiment {
                    return .merge(
                        .cancel(id: CancelID.activeExperimentCheck),
                        .cancel(id: CancelID.permission),
                        .cancel(id: CancelID.countdown)
                    )
                }
                state.phase = .details
                return .merge(
                    .cancel(id: CancelID.activeExperimentCheck),
                    .cancel(id: CancelID.permission),
                    .cancel(id: CancelID.countdown),
                    .cancel(id: CancelID.openSession)
                )
            }
        }
    }

    private func beginCountdown(_ state: inout State) -> Effect<Action> {
        state.phase = .countdown(nil)
        let experimentID = state.experiment.id
        return .merge(
            .run { _ in
                await watchExperimentClient.requestPhoneSession(experimentID)
            }
            .cancellable(id: CancelID.openSession, cancelInFlight: true),
            .run { send in
                for _ in 0..<4 {
                    try await Task.sleep(for: .seconds(1))
                    await send(.countdownTick)
                }
            }
            .cancellable(id: CancelID.countdown, cancelInFlight: true)
        )
    }
}
