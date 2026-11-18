//
//  ExperimentFeature.swift
//  Researchers
//
//  Created by 정홍섭 on 11/16/26.
//

import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

@Reducer
struct ExperimentFeature {
    enum Overlay: Equatable { case stop, end }
    enum CloseResult: Equatable { case paused, completed }
    enum TimerStartSyncResult {
        case confirmed(WatchExperimentSnapshot)
        case retry
        case rejected
    }

    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var snapshot: WatchExperimentSnapshot?
        var isLoading = true
        var overlay: Overlay?
        var isClosing = false
        var closeResult: CloseResult?
        var errorMessage: String?
        var pendingTimerIDs: Set<UUID> = []
        var localTimers: [WatchPendingTimer] = []
        var syncingTimerID: UUID?
        /// 삭제를 누른 즉시 목록에서 숨기고, iPhone이 거절하면 다시 표시합니다.
        var deletingTimerIDs: Set<UUID> = []

        var displayedTimers: [WatchTimerSnapshot] {
            let remote = (snapshot?.timers ?? []).filter { !deletingTimerIDs.contains($0.id) }
            let remoteIDs = Set(remote.map(\.id))
            return remote + localTimers.filter { !remoteIDs.contains($0.id) }
                .map { $0.snapshot(at: .now) }
        }
    }

    enum Action {
        case appeared
        case disappeared
        case snapshotReceived(WatchExperimentSnapshot)
        case snapshotRequestFailed
        case timerCommandTapped(UUID, WatchExperimentCommand.Operation)
        case timerCommandFinished(UUID, Bool)
        case timerStartTapped(Int)
        case retryPendingTimer
        case timerStartSyncFinished(UUID, TimerStartSyncResult)
        case pauseTapped
        case endTapped
        case overlayDismissed
        case stopConfirmed
        case endDelayElapsed
        case closeSucceeded(WatchExperimentCommand.Operation)
        case closeFailed
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case snapshots
        case initialSnapshot
        case endDelay
        case pendingTimerRetry
    }

    @Dependency(\.watchExperimentClient) private var watchExperimentClient
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                let experimentID = state.experimentID
                state.isLoading = state.snapshot == nil
                state.localTimers = WatchPendingTimerStore.shared.timers(for: experimentID)
                return .merge(
                    .run { send in
                        for await snapshot in await watchExperimentClient.snapshots() {
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

            case let .snapshotReceived(snapshot):
                guard snapshot.experiment.id == state.experimentID,
                      state.snapshot.map({ current in
                          snapshot.revision > current.revision
                              || snapshot.revision == current.revision
                                  && snapshot.recordedAt >= current.recordedAt
                      }) ?? true else { return .none }
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
                if snapshot.experiment.status == .paused {
                    state.closeResult = .paused
                    state.overlay = nil
                } else if snapshot.experiment.status == .completed {
                    state.closeResult = .completed
                    state.overlay = nil
                }
                return state.localTimers.isEmpty ? .none : .send(.retryPendingTimer)

            case .pauseTapped:
                guard state.overlay == nil, !state.isClosing else { return .none }
                state.overlay = .stop
                state.errorMessage = nil
                return .none

            case let .timerStartTapped(seconds):
                guard let snapshot = state.snapshot, snapshot.mode == .procedure,
                      snapshot.experiment.status == .running,
                      snapshot.protocolTimerSeconds.contains(seconds), seconds > 0,
                      snapshot.timers.count + state.localTimers.count
                        < ExperimentTimerCollection.maximumCount,
                      state.overlay == nil, !state.isClosing else { return .none }
                let timer = ExperimentTimer(
                    id: uuid(), durationSeconds: seconds, startedAt: now
                )
                let pending = WatchPendingTimer(
                    experimentID: state.experimentID, timer: timer, lastObservedAt: now
                )
                state.localTimers.append(pending)
                WatchPendingTimerStore.shared.add(pending)
                return .send(.retryPendingTimer)

            case let .timerCommandTapped(id, operation) where
                state.localTimers.contains(where: { $0.id == id }):
                guard state.syncingTimerID != id,
                      let index = state.localTimers.firstIndex(where: { $0.id == id }) else {
                    return .none
                }
                var pending = state.localTimers[index]
                switch operation {
                case .pauseTimer:
                    guard pending.timer.status == .running else { return .none }
                    pending.timer.pause(at: now)
                case .resumeTimer:
                    guard pending.timer.status == .paused else { return .none }
                    pending.timer.resume(at: now)
                case .deleteTimer:
                    guard pending.timer.status == .paused
                            || pending.timer.remainingSeconds(at: now) == 0 else { return .none }
                    state.localTimers.remove(at: index)
                    WatchPendingTimerStore.shared.remove(id)
                    return .none
                default:
                    return .none
                }
                pending.lastObservedAt = now
                state.localTimers[index] = pending
                WatchPendingTimerStore.shared.update(pending)
                return .none

            case let .timerCommandTapped(id, operation):
                guard !state.pendingTimerIDs.contains(id),
                      let timer = state.snapshot?.timers.first(where: { $0.id == id }),
                      state.overlay == nil, !state.isClosing else { return .none }
                let isFinished = timer.status == .finished || timer.remaining(at: .now) == 0
                guard (operation == .deleteTimer && (isFinished || timer.status == .paused))
                        || (operation == .pauseTimer && timer.status == .running && !isFinished)
                        || (operation == .resumeTimer && timer.status == .paused && !isFinished)
                else { return .none }
                state.pendingTimerIDs.insert(id)
                if operation == .deleteTimer { state.deletingTimerIDs.insert(id) }
                state.errorMessage = nil
                let experimentID = state.experimentID
                return .run { send in
                    do {
                        let snapshotResponse = try await watchExperimentClient.send(
                            WatchExperimentCommand(
                                operation: .snapshot, experimentID: experimentID
                            )
                        )
                        guard snapshotResponse.phase == .completed,
                              let snapshot = snapshotResponse.snapshot else {
                            throw snapshotResponse.error ?? WatchExperimentError.resultUnknown
                        }
                        let command = WatchExperimentCommand(
                            operation: operation, experimentID: experimentID,
                            expectedRevision: snapshot.revision, targetID: id
                        )
                        var response = try await watchExperimentClient.send(command)
                        for _ in 0..<100 {
                            if response.phase == .completed { break }
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
                        let refreshed = try await watchExperimentClient.send(
                            WatchExperimentCommand(
                                operation: .snapshot, experimentID: experimentID
                            )
                        )
                        if let snapshot = refreshed.snapshot {
                            await send(.snapshotReceived(snapshot))
                        }
                        await send(.timerCommandFinished(id, true))
                    } catch {
                        await send(.timerCommandFinished(id, false))
                    }
                }

            case let .timerCommandFinished(id, succeeded):
                state.pendingTimerIDs.remove(id)
                state.deletingTimerIDs.remove(id)
                if !succeeded {
                    state.errorMessage = "타이머를 변경하지 못했어요. 다시 시도해 주세요."
                }
                return .none

            case .retryPendingTimer:
                guard state.syncingTimerID == nil,
                      let pending = state.localTimers.first else { return .none }
                let pendingID = pending.id
                let requestID = uuid()
                state.syncingTimerID = pendingID
                let experimentID = state.experimentID
                return .run { send in
                    do {
                        let response = try await watchExperimentClient.send(
                            WatchExperimentCommand(
                                operation: .snapshot, experimentID: experimentID
                            )
                        )
                        guard response.phase == .completed, let snapshot = response.snapshot else {
                            throw response.error ?? WatchExperimentError.resultUnknown
                        }
                        if snapshot.timers.contains(where: { $0.id == pendingID }) {
                            await send(.timerStartSyncFinished(
                                pendingID, .confirmed(snapshot)
                            ))
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
                        var result = try await watchExperimentClient.send(command)
                        for _ in 0..<100 {
                            if result.phase == .completed { break }
                            if result.phase == .failed || result.phase == .unknown {
                                throw result.error ?? WatchExperimentError.resultUnknown
                            }
                            try await Task.sleep(for: .milliseconds(200))
                            result = try await watchExperimentClient.send(
                                WatchExperimentCommand(
                                    operation: .requestStatus, experimentID: experimentID,
                                    targetID: command.requestID
                                )
                            )
                        }
                        guard result.phase == .completed else {
                            throw WatchExperimentError.deliveryTimeout
                        }
                        let refreshed = try await watchExperimentClient.send(
                            WatchExperimentCommand(
                                operation: .snapshot, experimentID: experimentID
                            )
                        )
                        if let snapshot = refreshed.snapshot,
                           snapshot.timers.contains(where: { $0.id == pendingID }) {
                            await send(.timerStartSyncFinished(
                                pendingID, .confirmed(snapshot)
                            ))
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

            case let .timerStartSyncFinished(id, result):
                guard state.syncingTimerID == id else { return .none }
                state.syncingTimerID = nil
                switch result {
                case let .confirmed(snapshot):
                    state.localTimers.removeAll { $0.id == id }
                    WatchPendingTimerStore.shared.remove(id)
                    return .concatenate(
                        .send(.snapshotReceived(snapshot)), .send(.retryPendingTimer)
                    )
                case .rejected:
                    state.localTimers.removeAll { $0.id == id }
                    WatchPendingTimerStore.shared.remove(id)
                    state.errorMessage = "iPhone 타이머 상태를 우선해 Watch 타이머를 제거했어요."
                    return .send(.retryPendingTimer)
                case .retry:
                    return .none
                }

            case .endTapped:
                guard state.overlay == nil, !state.isClosing else { return .none }
                state.overlay = .end
                state.errorMessage = nil
                return .run { send in
                    try await Task.sleep(for: .seconds(3))
                    await send(.endDelayElapsed)
                }
                .cancellable(id: CancelID.endDelay, cancelInFlight: true)

            case .overlayDismissed:
                guard !state.isClosing else { return .none }
                state.overlay = nil
                state.errorMessage = nil
                return .cancel(id: CancelID.endDelay)

            case .stopConfirmed:
                guard state.overlay == .stop, !state.isClosing else { return .none }
                return close(.pause, state: &state)

            case .endDelayElapsed:
                guard state.overlay == .end, !state.isClosing else { return .none }
                return close(.complete, state: &state)

            case let .closeSucceeded(operation):
                state.isClosing = false
                state.overlay = nil
                state.closeResult = operation == .pause ? .paused : .completed
                return .none

            case .closeFailed:
                state.isClosing = false
                state.overlay = nil
                state.errorMessage = "iPhone에서 실험을 변경하지 못했어요. "
                    + "다시 시도해 주세요."
                return .none

            case .snapshotRequestFailed:
                if state.snapshot == nil { state.isLoading = false }
                return .none

            case .disappeared:
                let stopObserving = Effect<Action>.merge(
                    .cancel(id: CancelID.snapshots),
                    .cancel(id: CancelID.initialSnapshot),
                    .cancel(id: CancelID.pendingTimerRetry)
                )
                guard state.overlay != .end else { return stopObserving }
                return .merge(stopObserving, .cancel(id: CancelID.endDelay))
            }
        }
    }

    private func close(
        _ operation: WatchExperimentCommand.Operation, state: inout State
    ) -> Effect<Action> {
        state.isClosing = true
        let experimentID = state.experimentID
        return .run { send in
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
                        expectedRevision: snapshot.revision
                    )
                    do {
                        var response = try await watchExperimentClient.send(command)
                        for _ in 0..<100 {
                            if response.phase == .completed { break }
                            if response.phase == .failed || response.phase == .unknown {
                                throw response.error ?? WatchExperimentError.resultUnknown
                            }
                            try await Task.sleep(for: .milliseconds(200))
                            response = try await watchExperimentClient.send(
                                WatchExperimentCommand(
                                    operation: .requestStatus,
                                    experimentID: experimentID,
                                    targetID: command.requestID
                                )
                            )
                        }
                        guard response.phase == .completed else {
                            throw WatchExperimentError.deliveryTimeout
                        }
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
