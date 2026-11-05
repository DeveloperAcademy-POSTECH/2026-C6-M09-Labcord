import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

extension WatchExperimentFeature {
    func activate(state: inout State) -> Effect<Action> {
        guard !state.isVisible else { return .none }
        _ = restorePending(state: &state)
        state.isVisible = true
        state.isReachable = false
        let streamID = uuid()
        state.streamID = streamID
        return .merge(
            observeRecords(streamID),
            .run { [client] send in
                let snapshots = await client.snapshots()
                for await snapshot in snapshots {
                    try Task.checkCancellation()
                    await send(.snapshotReceived(streamID, snapshot))
                }
                guard !Task.isCancelled else { return }
                await send(.streamEnded(streamID))
            }
            .cancellable(id: CancelID.stream, cancelInFlight: true),
            .run { [client, clock] send in
                while !Task.isCancelled {
                    let reachable = await client.isReachable()
                    await send(.connectionChanged(streamID, reachable))
                    try await clock.sleep(for: .seconds(1))
                }
            }
            .cancellable(id: CancelID.connection, cancelInFlight: true)
        )
    }

    func reduceLifecycle(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .snapshotReceived(id, snapshot):
            guard state.isVisible, state.streamID == id else { return .none }
            accept(snapshot, state: &state)
            if state.countdownID == nil { return .cancel(id: CancelID.countdown) }
            return .none
        case let .streamEnded(id):
            guard state.streamID == id else { return .none }
            return endObservation(state: &state)
        case let .connectionChanged(id, reachable):
            guard state.streamID == id, state.isVisible else { return .none }
            let reconnected = !state.isReachable && reachable
            state.isReachable = reachable
            state.currentTime = now
            if !reachable, state.pending != nil { state.pending?.phase = .uncertain }
            return reconnected ? .send(.refresh) : .none
        case let .tick(date):
            state.currentTime = date
            return .none
        default:
            return .none
        }
    }

    private func endObservation(state: inout State) -> Effect<Action> {
    state.isVisible = false
    state.isRequestingPermission = false
    state.cleanupRequestID = nil
    state.isReachable = false
    state.streamID = nil
    state.startToken = nil
    state.countdownID = nil
    state.authorization = nil
    state.isPreparingInterruption = false
    if case .countdown = state.screen { state.screen = .experiment }
    if let pending = state.pending,
       WatchRequestPolicy.canAbandon(pending.command.operation) {
        state.pending = nil
    } else if state.pending != nil {
        state.pending?.phase = .uncertain
    }
    state.message = "상태 수신이 중단됐어요. 다시 연결해주세요."
    return .merge(
        .merge(CancelID.all.map { .cancel(id: $0) }),
        .send(.recording(.recoveryFailed))
    )
    }

    func accept(_ snapshot: WatchExperimentSnapshot, state: inout State) {
        let id = snapshot.experiment.id
        guard id == state.selectedID else { return }
        guard WatchPresentationRules.accepts(
            revision: snapshot.revision, previous: state.snapshots[id]?.revision
        ) else { return }
        state.snapshots[id] = snapshot
        if snapshot.experiment.status != .ready, case .countdown = state.screen {
            state.startToken = nil
            state.countdownID = nil
            state.screen = .experiment
        }
        if let index = state.experiments.firstIndex(where: { $0.id == id }) {
            state.experiments[index] = snapshot.experiment
        }
    }
}
