import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

extension WatchExperimentFeature.State {
    var snapshot: WatchExperimentSnapshot? { selectedID.flatMap { snapshots[$0] } }
    var canResume: Bool { [.paused, .completed].contains(snapshot?.experiment.status) }

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
        let observationID = uuid()
        state.recordObservationID = observationID
        state.recordObservationReady = false
        state.recording.isIntegrated = false
        return .merge(
            observeRecords(streamID, observationID: observationID),
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
            deferPhoneSessionDuringList(snapshot, state: &state)
            followPhoneSessionIfSafe(snapshot, state: &state)
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
        guard reconnected else { return .none }
        return .merge(
            .send(.refresh),
            .send(.recording(.delegate(.local(.reconcile))))
        )
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
        state.deferredPhoneSession = nil
        let interruptionPending = state.isPreparingInterruption
        state.interruptionNeedsConfirmation = state.interruptionNeedsConfirmation
            || interruptionPending
        state.isVisible = false
        state.isRequestingPermission = false
        state.cleanupRequestID = nil
        state.isReachable = false
        state.connectionStatus = .activationFailed
        state.streamID = nil
        state.recordObservationID = nil
        state.recordObservationReady = false
        state.startToken = nil
        state.countdownID = nil
        state.authorization = nil
        state.isPreparingInterruption = false
        state.interruptionAttemptID = nil
        if case .countdown = state.screen { state.screen = .experiment }
        suspendPendingRequest(state: &state)
        state.message = state.interruptionNeedsConfirmation
            ? "실험 중단·종료 요청이 완료되지 않았어요. iPhone 상태를 확인해주세요."
            : "상태 수신이 중단됐어요. 다시 연결해주세요."
        return .merge(
            .merge(CancelID.all.map { .cancel(id: $0) }),
            .send(.recording(.recoveryFailed))
        )
    }

    private func deferPhoneSessionDuringList(
        _ snapshot: WatchExperimentSnapshot, state: inout State
    ) {
        guard state.pending?.command.operation == .list, snapshot.phoneSessionActive != nil,
              abs(snapshot.recordedAt.timeIntervalSince(now)) <= 30,
              state.deferredPhoneSession.map({ snapshot.recordedAt >= $0.recordedAt }) ?? true
        else { return }
        if snapshot.phoneSessionActive == true, snapshot.experiment.status == .running {
            state.deferredPhoneSession = snapshot
        } else if state.deferredPhoneSession?.experiment.id == snapshot.experiment.id {
            state.deferredPhoneSession = nil
        }
    }

    func followPhoneSessionIfSafe(
        _ snapshot: WatchExperimentSnapshot, state: inout State
    ) {
        guard snapshot.phoneSessionActive == true,
              snapshot.experiment.status == .running,
              abs(snapshot.recordedAt.timeIntervalSince(now)) <= 30,
              state.hasRestoredPending, !state.pendingRecoveryFailed,
              state.pending == nil, !state.isRequestingPermission,
              !state.isPreparingInterruption, !state.interruptionNeedsConfirmation,
              state.cleanupRequestID == nil, state.authorization == nil,
              state.countdownID == nil, state.recording.focusedID == nil,
              !state.recording.records.values.contains(where: { !$0.isSettled }) else { return }

        let id = snapshot.experiment.id
        if let selectedID = state.selectedID, selectedID != id {
            if state.screen == .experiment, state.message == nil {
                state.message = "iPhone에서 다른 실험이 진행 중이에요."
            }
            return
        }
        guard state.selectedID == nil, state.screen == .selection,
              WatchPresentationRules.accepts(
                revision: snapshot.revision, previous: state.snapshots[id]?.revision
              ) else { return }
        state.selectedID = id
        state.screen = .experiment
        if !state.experiments.contains(where: { $0.id == id }) {
            state.experiments.append(snapshot.experiment)
        }
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

extension WatchExperimentFeature {
    func deactivate(state: inout State) -> Effect<Action> {
        state.deferredPhoneSession = nil
        if state.isPreparingInterruption {
            state.isPreparingInterruption = false
            state.interruptionAttemptID = nil
            state.interruptionNeedsConfirmation = true
            state.message = "실험 중단·종료 요청이 완료되지 않았어요. iPhone 상태를 확인해주세요."
        }
        state.isVisible = false
        state.isRequestingPermission = false
        state.cleanupRequestID = nil
        state.streamID = nil
        state.recordObservationID = nil
        state.recordObservationReady = false
        state.authorization = nil
        state.countdownID = nil
        if case .countdown = state.screen {
            state.screen = .experiment
            state.startToken = nil
        }
        suspendPendingRequest(state: &state)
        return .merge(
            .merge(CancelID.all.map { .cancel(id: $0) }),
            .send(.recording(.interrupted))
        )
    }
}
