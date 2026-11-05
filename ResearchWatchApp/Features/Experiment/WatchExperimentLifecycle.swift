import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

extension WatchExperimentFeature.State {
    var selectedTitle: String {
        snapshot?.experiment.title
            ?? experiments.first { $0.id == selectedID }?.title ?? "실험 선택"
    }

    var canReviewCompletedExperiment: Bool {
        cleanupRequestID != nil && recording.isIntegrated
            && snapshot?.experiment.status == .completed && pending == nil
            && !recording.hasUnsettledRecords(in: selectedID)
    }

    var canOperate: Bool {
        isVisible && streamID != nil && pending == nil && isReachable
            && snapshot != nil && !isPreparingInterruption && !pendingRecoveryFailed
    }

    mutating func clearMessageUnlessInterruptionUnconfirmed() {
        if !interruptionNeedsConfirmation { message = nil }
    }
}

extension WatchExperimentFeature {
    func activate(state: inout State) -> Effect<Action> {
        guard !state.isVisible else { return .none }
        _ = restorePending(state: &state)
        state.isVisible = true
        state.isReachable = false
        state.connectionStatus = .activating
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
                    let status = await client.connectionStatus()
                    await send(.connectionStatusChanged(streamID, status))
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
            return updateConnectionStatus(
                id, status: reachable ? .reachable : .unreachable, state: &state
            )
        case let .connectionStatusChanged(id, status):
            return updateConnectionStatus(id, status: status, state: &state)
        case .retryConnection:
            return retryConnection(state: &state)
        case let .tick(date):
            state.currentTime = date
            return .none
        default:
            return .none
        }
    }

    private func updateConnectionStatus(
        _ id: UUID, status: WatchConnectionStatus, state: inout State
    ) -> Effect<Action> {
        guard state.streamID == id, state.isVisible else { return .none }
        let reachable = status == .reachable
        let reconnected = !state.isReachable && reachable
        state.connectionStatus = status
        state.isReachable = reachable
        state.currentTime = now
        if !reachable, state.pending != nil { state.pending?.phase = .uncertain }
        return reconnected ? .send(.refresh) : .none
    }

    private func retryConnection(state: inout State) -> Effect<Action> {
        if !state.isVisible {
            return .merge(
                activate(state: &state),
                .run { [client] _ in await client.retryActivation() }
            )
        }
        guard let streamID = state.streamID else { return .none }
        if state.isReachable { return .send(.refresh) }
        state.connectionStatus = .activating
        return .run { [client] send in
            await client.retryActivation()
            await send(.connectionStatusChanged(streamID, await client.connectionStatus()))
        }
    }

    private func endObservation(state: inout State) -> Effect<Action> {
    let interruptionPending = state.isPreparingInterruption
    state.interruptionNeedsConfirmation = state.interruptionNeedsConfirmation
        || interruptionPending
    state.isVisible = false
    state.isRequestingPermission = false
    state.cleanupRequestID = nil
    state.isReachable = false
    state.connectionStatus = .activationFailed
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
    state.message = state.interruptionNeedsConfirmation
        ? "실험 중단·종료 요청이 완료되지 않았어요. iPhone 상태를 확인해주세요."
        : "상태 수신이 중단됐어요. 다시 연결해주세요."
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
