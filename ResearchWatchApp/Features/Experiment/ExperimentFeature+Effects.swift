import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

extension ExperimentFeature {
    func observeExperiment(experimentID: UUID) -> Effect<Action> {
        .merge(
            .run { send in
                for await snapshot in await watchExperimentClient.snapshots(for: experimentID) {
                    await send(.snapshotReceived(snapshot))
                }
            }
            .cancellable(id: CancelID.snapshots, cancelInFlight: true),
            .run { send in
                while !Task.isCancelled {
                    await send(.retryPendingTimer)
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            .cancellable(id: CancelID.pendingTimerRetry, cancelInFlight: true)
        )
    }

    func receiveSnapshot(
        _ snapshot: WatchExperimentSnapshot, state: inout State
    ) -> Effect<Action> {
        guard snapshot.experiment.id == state.experimentID,
              state.snapshot.map({ current in
                  snapshot.revision > current.revision
                      || snapshot.revision == current.revision
                          && snapshot.recordedAt >= current.recordedAt
              }) ?? true else { return .none }
        state.snapshot = snapshot
        let remoteIDs = Set(snapshot.timers.map(\.id))
        for pending in state.localTimers where remoteIDs.contains(pending.id) {
            WatchPendingTimerStore.shared.remove(pending.id)
        }
        state.localTimers.removeAll { remoteIDs.contains($0.id) }
        let available = max(0, ExperimentTimerCollection.maximumCount
            - snapshot.timers.count)
        if state.localTimers.count > available {
            for pending in state.localTimers.dropFirst(available) {
                WatchPendingTimerStore.shared.remove(pending.id)
            }
            state.localTimers = Array(state.localTimers.prefix(available))
            state.errorMessage = "iPhone 타이머가 우선되어 Watch 타이머 일부를 제거했어요."
        }
        switch snapshot.experiment.status {
        case .running:
            state.hasObservedRunning = true
        case .paused where state.hasObservedRunning:
            state.closeResult = .paused
            state.overlay = nil
        case .completed where state.hasObservedRunning:
            state.closeResult = .completed
            state.overlay = nil
        default:
            break
        }
        return state.localTimers.isEmpty ? .none : .send(.retryPendingTimer)
    }

    func timerCommandEffect(
        id: UUID, operation: WatchExperimentCommand.Operation, snapshot: WatchExperimentSnapshot
    ) -> Effect<Action> {
        .run { send in
            do {
                let updated = try await performControl(operation, targetID: id, from: snapshot)
                if let updated {
                    await send(.snapshotReceived(updated))
                }
                await send(.timerCommandFinished(id, failure: nil))
            } catch is CancellationError {
                return
            } catch {
                await send(.timerCommandFinished(id, failure: controlErrorMessage(for: error)))
            }
        }
        .cancellable(id: CancelID.controls)
    }

    func pendingTimerSyncEffect(
        _ pending: WatchPendingTimer, requestID: UUID, experimentID: UUID
    ) -> Effect<Action> {
        let pendingID = pending.id
        return .run { send in
            do {
                let snapshot = try await currentSnapshot(experimentID: experimentID)
                if snapshot.timers.contains(where: { $0.id == pendingID }) {
                    await send(.timerStartSyncFinished(pendingID, .confirmed(snapshot)))
                    return
                }
                guard snapshot.experiment.status == .running,
                      snapshot.timers.count < ExperimentTimerCollection.maximumCount else {
                    await send(.timerStartSyncFinished(pendingID, .rejected))
                    return
                }
                let command = WatchExperimentCommand(
                    requestID: requestID, operation: .startTimer,
                    experimentID: experimentID,
                    expectedRevision: snapshot.revision,
                    targetID: pendingID,
                    durationSeconds: pending.timer.durationSeconds,
                    timerStartedAt: pending.timer.startedAt,
                    timerPauseIntervals: pending.timer.pauseIntervals
                )
                let confirmed = try await confirmedSnapshot(for: command)
                if let snapshot = confirmed,
                   snapshot.timers.contains(where: { $0.id == pendingID }) {
                    await send(.timerStartSyncFinished(pendingID, .confirmed(snapshot)))
                } else {
                    await send(.timerStartSyncFinished(pendingID, .retry))
                }
            } catch let error as WatchExperimentError {
                let rejectsStart: Bool
                switch error {
                case .invalidPayload, .invalidState, .experimentNotFound,
                     .activeExperimentConflict:
                    rejectsStart = true
                default:
                    rejectsStart = false
                }
                await send(.timerStartSyncFinished(
                    pendingID, rejectsStart ? .rejected : .retry
                ))
            } catch {
                await send(.timerStartSyncFinished(pendingID, .retry))
            }
        }
        .cancellable(id: CancelID.controls)
    }

    func currentSnapshot(experimentID: UUID) async throws -> WatchExperimentSnapshot {
        let response = try await watchExperimentClient.send(
            WatchExperimentCommand(operation: .snapshot, experimentID: experimentID)
        )
        guard response.phase == .completed, let snapshot = response.snapshot else {
            throw response.error ?? WatchExperimentError.resultUnknown
        }
        return snapshot
    }

    func startPendingTimer(seconds: Int, state: inout State) -> Effect<Action> {
        let timer = ExperimentTimer(id: uuid(), durationSeconds: seconds, startedAt: now)
        let pending = WatchPendingTimer(
            experimentID: state.experimentID, timer: timer, lastObservedAt: now
        )
        state.localTimers.append(pending)
        WatchPendingTimerStore.shared.add(pending)
        return .send(.retryPendingTimer)
    }

    func close(
        _ operation: WatchExperimentCommand.Operation, state: inout State
    ) -> Effect<Action> {
        state.isClosing = true
        let experimentID = state.experimentID
        let lastSnapshot = state.snapshot
        return .run { send in
            do {
                let snapshot: WatchExperimentSnapshot
                if let lastSnapshot {
                    snapshot = lastSnapshot
                } else {
                    snapshot = try await currentSnapshot(experimentID: experimentID)
                }
                _ = try await performControl(operation, targetID: nil, from: snapshot)
                await send(.closeSucceeded(operation))
            } catch is CancellationError {
                return
            } catch {
                await send(.closeFailed(controlErrorMessage(for: error)))
            }
        }
        .cancellable(id: CancelID.controls)
    }

    private func controlErrorMessage(for error: Error) -> String {
        switch error as? WatchExperimentError {
        case .resultUnknown, .deliveryTimeout:
            "iPhone에서 처리 결과를 확인할 수 없어요. 실험 상태를 확인해 주세요."
        case .notReachable:
            "iPhone에 연결한 뒤 다시 시도해 주세요."
        default:
            "iPhone에서 요청을 처리하지 못했어요. 다시 시도해 주세요."
        }
    }

    private func performControl(
        _ operation: WatchExperimentCommand.Operation, targetID: UUID?,
        from initial: WatchExperimentSnapshot
    ) async throws -> WatchExperimentSnapshot? {
        var snapshot = initial
        for attempt in 0..<3 {
            let command = WatchExperimentCommand(
                operation: operation, experimentID: snapshot.experiment.id,
                expectedRevision: snapshot.revision, targetID: targetID
            )
            if snapshot.reflects(command) { return snapshot }
            do {
                return try await confirmedSnapshot(for: command)
            } catch WatchExperimentError.staleRevision where attempt < 2 {
                snapshot = try await currentSnapshot(experimentID: initial.experiment.id)
            }
        }
        throw WatchExperimentError.staleRevision
    }

    private func confirmedSnapshot(
        for command: WatchExperimentCommand
    ) async throws -> WatchExperimentSnapshot? {
        var awaitingResult = false
        while true {
            try Task.checkCancellation()
            do {
                return try await watchExperimentClient.sendRecovering(command).snapshot
            } catch let error as WatchExperimentError {
                switch error {
                case .deliveryTimeout, .resultUnknown:
                    awaitingResult = true
                case .notReachable where awaitingResult:
                    break
                default:
                    throw error
                }
            }
            guard let id = command.experimentID else { throw WatchExperimentError.invalidPayload }
            let current = try? await currentSnapshot(experimentID: id)
            if let current, current.reflects(command) { return current }
            if let result = try await completedStatus(
                for: command, hasCurrentState: current != nil
            ) {
                return result.snapshot
            }
            try await Task.sleep(for: .seconds(2))
        }
    }

    private func completedStatus(
        for command: WatchExperimentCommand, hasCurrentState: Bool
    ) async throws -> WatchExperimentResponse? {
        let query = WatchExperimentCommand(
            operation: .requestStatus, experimentID: command.experimentID,
            targetID: command.requestID
        )
        guard let status = try? await watchExperimentClient.send(query),
              status.queriedRequestID == command.requestID else { return nil }
        switch status.phase {
        case .completed: return status
        case .failed: throw status.error ?? WatchExperimentError.resultUnknown
        case .unknown where hasCurrentState: throw WatchExperimentError.resultUnknown
        default: return nil
        }
    }
}

private extension WatchExperimentSnapshot {
    func reflects(_ command: WatchExperimentCommand) -> Bool {
        guard experiment.id == command.experimentID, revision >= (command.expectedRevision ?? 0)
        else { return false }
        let timer = timers.first { $0.id == command.targetID }
        switch command.operation {
        case .pause: return experiment.status == .paused
        case .complete: return experiment.status == .completed
        case .startTimer: return timer != nil
        case .pauseTimer: return timer?.status == .paused
        case .resumeTimer: return timer?.status == .running
        case .deleteTimer: return timer == nil
        default: return false
        }
    }
}
