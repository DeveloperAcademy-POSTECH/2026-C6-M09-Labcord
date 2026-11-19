import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

enum ExperimentStartPhase: Equatable {
    case details
    case checkingActiveExperiment
    case requestingPermission
    case permissionDenied
    case countdown(Int?)
    case waitingForPhone
    case failed(WatchExperimentError)
    case experiment
}

@Reducer
struct ExperimentStartFeature {
    @ObservableState
    struct State: Equatable {
        let experiment: WatchExperimentSummary
        var phase: ExperimentStartPhase = .details
        var isActiveExperimentConflictPresented = false
        var epoch: WatchStateEpoch?
        var openRequest: WatchSessionOpenRequest?
    }

    enum Action {
        case startTapped
        case activeExperimentChecked(WatchExperimentList)
        case activeExperimentCheckFailed(WatchExperimentError)
        case activeExperimentConflictDismissed
        case permissionUpdated(PermissionStatus)
        case permissionRecheckTapped
        case countdownTick
        case openFinished(UUID, WatchExperimentError?)
        case enteredBackground
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
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startTapped:
                let canStart: Bool
                switch state.phase {
                case .details, .failed: canStart = true
                default: canStart = false
                }
                guard canStart, !state.isActiveExperimentConflictPresented else { return .none }
                state.phase = .checkingActiveExperiment
                return .run { send in
                    do {
                        let list = try await watchExperimentClient.list()
                        await send(.activeExperimentChecked(list))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.activeExperimentCheckFailed(
                            error as? WatchExperimentError ?? .resultUnknown
                        ))
                    }
                }
                .cancellable(id: CancelID.activeExperimentCheck, cancelInFlight: true)

            case let .activeExperimentChecked(list):
                guard state.phase == .checkingActiveExperiment else { return .none }
                guard list.experiments.contains(where: { $0.id == state.experiment.id }) else {
                    state.phase = .failed(.experimentNotFound)
                    return .none
                }
                if list.experiments.contains(where: {
                    $0.status == .running && $0.id != state.experiment.id
                }) {
                    state.phase = .details
                    state.isActiveExperimentConflictPresented = true
                    return .none
                }
                guard let epoch = list.version?.epoch else {
                    state.phase = .failed(.unsupportedVersion)
                    return .none
                }
                state.epoch = epoch
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

            case let .activeExperimentCheckFailed(error):
                guard state.phase == .checkingActiveExperiment else { return .none }
                state.phase = .failed(error)
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
                    state.phase = .details
                    return .send(.startTapped)
                }
                return .none

            case .countdownTick:
                guard case let .countdown(number) = state.phase else { return .none }
                switch number {
                case nil: state.phase = .countdown(3)
                case 1: return openOnPhone(&state)
                case let .some(value): state.phase = .countdown(value - 1)
                }
                return .none

            case let .openFinished(id, error):
                guard state.phase == .waitingForPhone, let request = state.openRequest,
                      request.requestID == id else { return .none }
                state.openRequest = nil
                if let error {
                    state.phase = .failed(error)
                    return cancel(request)
                }
                state.phase = .experiment
                return .none

            case .enteredBackground:
                switch state.phase {
                case .checkingActiveExperiment, .countdown:
                    return leaveStart(&state)
                default:
                    return .none
                }

            case .disappeared:
                guard state.phase != .experiment else { return .none }
                return leaveStart(&state)
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

    private func openOnPhone(_ state: inout State) -> Effect<Action> {
        let request = WatchSessionOpenRequest(
            experimentID: state.experiment.id, requestID: uuid(), requestedAt: now,
            expiresAt: now.addingTimeInterval(WatchSessionOpenRequest.lifetime), epoch: state.epoch
        )
        state.openRequest = request
        state.phase = .waitingForPhone
        return .run { send in
            do {
                try await watchExperimentClient.requestPhoneSession(request)
                await send(.openFinished(request.requestID, nil))
            } catch is CancellationError {
                return
            } catch {
                await send(.openFinished(
                    request.requestID, error as? WatchExperimentError ?? .resultUnknown
                ))
            }
        }
        .cancellable(id: CancelID.openSession, cancelInFlight: true)
    }

    private func leaveStart(_ state: inout State) -> Effect<Action> {
        let request = state.openRequest
        state.openRequest = nil
        state.phase = .details
        return .merge(
            .cancel(id: CancelID.activeExperimentCheck),
            .cancel(id: CancelID.permission),
            .cancel(id: CancelID.countdown),
            .cancel(id: CancelID.openSession),
            request.map(cancel) ?? .none
        )
    }

    private func cancel(_ request: WatchSessionOpenRequest) -> Effect<Action> {
        .run { _ in await watchExperimentClient.cancelPhoneSession(request) }
    }
}
