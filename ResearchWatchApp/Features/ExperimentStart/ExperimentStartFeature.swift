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
    case failed(WatchExperimentError?)
    case experiment

    var hasRequestedSession: Bool {
        switch self {
        case .countdown, .waitingForPhone: true
        default: false
        }
    }
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
        case phoneSessionConfirmed
        case startFailed(WatchExperimentError?)
        case retryTapped
        case cancelTapped
        case becameInactive
        case disappeared
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case start
        case openSession
    }

    @Dependency(\.microphonePermissionClient) private var microphonePermission
    @Dependency(\.watchExperimentClient) private var watchExperimentClient
    @Dependency(\.continuousClock) private var clock

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startTapped:
                guard state.phase == .details,
                      !state.isActiveExperimentConflictPresented else { return .none }
                state.phase = .checkingActiveExperiment
                return checkExperiments(for: state.experiment.id)

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
                    .cancellable(id: CancelID.start, cancelInFlight: true)
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
                    state.phase = .details
                    return .send(.startTapped)
                }
                return .none

            case .countdownTick:
                guard case let .countdown(number) = state.phase else { return .none }
                switch number {
                case nil: state.phase = .countdown(3)
                case 1:
                    state.phase = .waitingForPhone
                    return confirmSession(state.experiment.id)
                case let .some(value): state.phase = .countdown(value - 1)
                }
                return .none

            case .phoneSessionConfirmed:
                guard state.phase == .waitingForPhone else { return .none }
                state.phase = .experiment
                return .none

            case let .startFailed(error):
                guard state.phase == .checkingActiveExperiment || state.phase == .waitingForPhone
                else { return .none }
                let shouldCancel = state.phase.hasRequestedSession
                state.phase = .failed(error)
                return stopStarting(state.experiment.id, notifyPhone: shouldCancel)

            case .retryTapped:
                if state.phase == .waitingForPhone {
                    let id = state.experiment.id
                    return .merge(requestSession(id), confirmSession(id))
                }
                guard case .failed = state.phase else { return .none }
                state.phase = .details
                return .send(.startTapped)

            case .cancelTapped, .becameInactive, .disappeared:
                guard state.phase != .experiment else { return .none }
                let shouldCancel = state.phase.hasRequestedSession
                let experimentID = state.experiment.id
                state.phase = .details
                return stopStarting(experimentID, notifyPhone: shouldCancel)
            }
        }
    }

    private func checkExperiments(for id: UUID) -> Effect<Action> {
        .run { send in
            do {
                let list = try await watchExperimentClient.list()
                guard list.contains(where: { $0.id == id }) else {
                    await send(.startFailed(.experimentNotFound))
                    return
                }
                let conflict = list.contains { $0.status == .running && $0.id != id }
                await send(.activeExperimentChecked(hasConflict: conflict))
            } catch {
                guard !Task.isCancelled else { return }
                await send(.startFailed(error as? WatchExperimentError))
            }
        }
        .cancellable(id: CancelID.start, cancelInFlight: true)
    }

    private func stopStarting(_ id: UUID, notifyPhone: Bool) -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.start),
            .cancel(id: CancelID.openSession),
            notifyPhone ? .run { _ in await watchExperimentClient.cancelPhoneSession(id) } : .none
        )
    }

    private func requestSession(_ id: UUID) -> Effect<Action> {
        .run { _ in await watchExperimentClient.requestPhoneSession(id) }
            .cancellable(id: CancelID.openSession, cancelInFlight: true)
    }

    private func beginCountdown(_ state: inout State) -> Effect<Action> {
        state.phase = .countdown(nil)
        return .merge(
            requestSession(state.experiment.id),
            .run { send in
                for _ in 0..<4 {
                    try await clock.sleep(for: .seconds(1))
                    await send(.countdownTick)
                }
            }
            .cancellable(id: CancelID.start, cancelInFlight: true)
        )
    }

    private func confirmSession(_ id: UUID) -> Effect<Action> {
        .run { send in
            var delay = 1
            while !Task.isCancelled {
                do {
                    if try await watchExperimentClient.activePhoneExperiment(id) != nil {
                        await send(.phoneSessionConfirmed)
                        return
                    }
                } catch let error as WatchExperimentError
                    where [.invalidState, .experimentNotFound, .invalidPayload].contains(error) {
                    await send(.startFailed(error))
                    return
                } catch {
                    try Task.checkCancellation()
                }
                try await clock.sleep(for: .seconds(delay))
                delay = min(delay * 2, 8)
            }
        }
        .cancellable(id: CancelID.start, cancelInFlight: true)
    }
}

extension WatchExperimentClient {
    func activePhoneExperiment(_ id: UUID) async throws -> WatchExperimentSummary? {
        let command = WatchExperimentCommand(operation: .snapshot, experimentID: id)
        let response = try await send(command)
        guard response.phase == .completed, let snapshot = response.snapshot,
              snapshot.experiment.id == id else {
            throw response.error ?? WatchExperimentError.invalidPayload
        }
        if snapshot.experiment.status == .completed { throw WatchExperimentError.invalidState }
        guard snapshot.experiment.status == .running, snapshot.phoneSessionActive == true
        else { return nil }
        return snapshot.experiment
    }
}
