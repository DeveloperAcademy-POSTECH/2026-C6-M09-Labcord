import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

extension ExperimentFeature {
    func observeExperiment(experimentID: UUID) -> Effect<Action> {
        .merge(
            .run { send in
                let snapshots = await watchExperimentClient.snapshots(experimentID)
                for await snapshot in snapshots {
                    await send(.snapshotReceived(snapshot))
                }
            }
            .cancellable(id: CancelID.snapshots, cancelInFlight: true),
            .run { send in
                do {
                    let response = try await watchExperimentClient.send(
                        WatchExperimentCommand(
                            operation: .snapshot,
                            experimentID: experimentID
                        )
                    )
                    guard response.phase == .completed,
                          let snapshot = response.snapshot else {
                        await send(.snapshotRequestFailed)
                        return
                    }
                    await send(.snapshotReceived(snapshot))
                } catch {
                    await send(.snapshotRequestFailed)
                }
            }
            .cancellable(id: CancelID.initialSnapshot, cancelInFlight: true),
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
              state.snapshot.map({ snapshot.isNewer(than: $0) }) ?? true else { return .none }
        let changedEpoch = state.snapshot.map { $0.epoch != snapshot.epoch } ?? false
        state.snapshot = snapshot
        state.isLoading = false
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
        case .ready where changedEpoch && state.hasObservedRunning:
            state.closeResult = .sessionUnavailable
            state.overlay = nil
        default:
            break
        }
        return state.localTimers.isEmpty ? .none : .send(.retryPendingTimer)
    }

    func timerCommandEffect(
        id: UUID, operation: WatchExperimentCommand.Operation, experimentID: UUID
    ) -> Effect<Action> {
        .run { send in
            do {
                let snapshot = try await currentSnapshot(experimentID: experimentID)
                let command = WatchExperimentCommand(
                    operation: operation, experimentID: experimentID,
                    expectedRevision: snapshot.revision, targetID: id,
                    expectedEpoch: snapshot.epoch
                )
                try await sendUntilCompleted(command, experimentID: experimentID)
                let refreshed = try await watchExperimentClient.send(
                    WatchExperimentCommand(operation: .snapshot, experimentID: experimentID)
                )
                if let snapshot = refreshed.snapshot {
                    await send(.snapshotReceived(snapshot))
                }
                await send(.timerCommandFinished(id, failure: nil))
            } catch let error as WatchExperimentError {
                await send(.timerCommandFinished(id, failure: error.rawValue))
            } catch {
                await send(.timerCommandFinished(id, failure: String(describing: error)))
            }
        }
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
                    timerPauseIntervals: pending.timer.pauseIntervals,
                    expectedEpoch: snapshot.epoch
                )
                try await sendUntilCompleted(command, experimentID: experimentID)
                let refreshed = try await watchExperimentClient.send(
                    WatchExperimentCommand(operation: .snapshot, experimentID: experimentID)
                )
                if let snapshot = refreshed.snapshot,
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

    func sendUntilCompleted(
        _ command: WatchExperimentCommand, experimentID: UUID
    ) async throws {
        var response = try await watchExperimentClient.send(command)
        for _ in 0..<100 {
            if response.phase == .completed { return }
            if response.phase == .failed || response.phase == .unknown {
                throw response.error ?? WatchExperimentError.resultUnknown
            }
            try await Task.sleep(for: .milliseconds(200))
            response = try await watchExperimentClient.send(
                WatchExperimentCommand(
                    operation: .requestStatus, experimentID: experimentID,
                    targetID: command.requestID
                )
            )
        }
        guard response.phase == .completed else {
            throw WatchExperimentError.deliveryTimeout
        }
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
        return .run { send in
            do {
                try await WatchVoiceRecordingService.shared.requireSettledRecordings(
                    in: experimentID
                )
            } catch {
                await send(.closeBlockedByAudio)
                return
            }
            do {
                for attempt in 0..<3 {
                    let snapshotResponse = try await watchExperimentClient.send(
                        WatchExperimentCommand(operation: .snapshot, experimentID: experimentID)
                    )
                    guard snapshotResponse.phase == .completed,
                          let snapshot = snapshotResponse.snapshot else {
                        throw snapshotResponse.error ?? WatchExperimentError.resultUnknown
                    }
                    let command = WatchExperimentCommand(
                        operation: operation, experimentID: experimentID,
                        expectedRevision: snapshot.revision, expectedEpoch: snapshot.epoch
                    )
                    do {
                        try await sendUntilCompleted(command, experimentID: experimentID)
                        await send(.closeSucceeded(operation))
                        return
                    } catch WatchExperimentError.staleRevision where attempt < 2 {
                        continue
                    }
                }
                throw WatchExperimentError.staleRevision
            } catch {
                await send(.closeFailed)
            }
        }
    }
}
