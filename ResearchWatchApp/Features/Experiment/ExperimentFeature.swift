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
        var overlay: Overlay?
        var isClosing = false
        var closeResult: CloseResult?
        var errorMessage: String?
        var pendingTimerIDs: Set<UUID> = []
        var localTimers: [WatchPendingTimer] = []
        var syncingTimerID: UUID?
        var hasObservedRunning = false

        var canAddTimer: Bool {
            snapshot?.experiment.status == .running
                && displayedTimers.count < ExperimentTimerCollection.maximumCount
        }

        var displayedTimers: [WatchTimerSnapshot] {
            let remote = snapshot?.timers ?? []
            let remoteIDs = Set(remote.map(\.id))
            return remote + localTimers.filter { !remoteIDs.contains($0.id) }
                .map { $0.snapshot(at: .now) }
        }
    }

    enum Action {
        case appeared
        case disappeared
        case snapshotReceived(WatchExperimentSnapshot)
        case timerCommandTapped(UUID, WatchExperimentCommand.Operation)
        case timerCommandFinished(UUID, failure: String?)
        case timerStartTapped(Int)
        case customTimerStartTapped(Int)
        case retryPendingTimer
        case timerStartSyncFinished(UUID, TimerStartSyncResult)
        case pauseTapped
        case endTapped
        case overlayDismissed
        case stopConfirmed
        case endDelayElapsed
        case closeSucceeded(WatchExperimentCommand.Operation)
        case closeFailed(String)
    }

    nonisolated enum CancelID: Hashable, Sendable {
        case snapshots
        case endDelay
        case pendingTimerRetry
        case controls
    }

    @Dependency(\.watchExperimentClient) var watchExperimentClient
    @Dependency(\.date.now) var now
    @Dependency(\.uuid) var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                let experimentID = state.experimentID
                state.localTimers = WatchPendingTimerStore.shared.timers(for: experimentID)
                return observeExperiment(experimentID: experimentID)

            case let .snapshotReceived(snapshot):
                return receiveSnapshot(snapshot, state: &state)

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
                return startPendingTimer(seconds: seconds, state: &state)

            case let .customTimerStartTapped(seconds):
                guard let snapshot = state.snapshot,
                      snapshot.experiment.status == .running,
                      seconds > 0, state.canAddTimer,
                      state.overlay == nil, !state.isClosing else { return .none }
                return startPendingTimer(seconds: seconds, state: &state)

            case let .timerCommandTapped(id, operation) where
                state.localTimers.contains { $0.id == id }:
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
                      let snapshot = state.snapshot,
                      let timer = snapshot.timers.first(where: { $0.id == id }),
                      state.overlay == nil, !state.isClosing else { return .none }
                let isFinished = timer.status == .finished || timer.remaining(at: .now) == 0
                guard (operation == .deleteTimer && (isFinished || timer.status == .paused))
                        || (operation == .pauseTimer && timer.status == .running && !isFinished)
                        || (operation == .resumeTimer && timer.status == .paused && !isFinished)
                else { return .none }
                state.pendingTimerIDs.insert(id)
                state.errorMessage = nil
                return timerCommandEffect(id: id, operation: operation, snapshot: snapshot)

            case let .timerCommandFinished(id, failure):
                state.pendingTimerIDs.remove(id)
                if let failure { state.errorMessage = failure }
                return .none

            case .retryPendingTimer:
                guard state.syncingTimerID == nil,
                      let pending = state.localTimers.first else { return .none }
                let pendingID = pending.id
                let requestID = uuid()
                state.syncingTimerID = pendingID
                let experimentID = state.experimentID
                return pendingTimerSyncEffect(
                    pending, requestID: requestID, experimentID: experimentID
                )

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

            case let .closeFailed(message):
                state.isClosing = false
                state.overlay = nil
                state.errorMessage = message
                return .none

            case .disappeared:
                state.pendingTimerIDs.removeAll()
                state.syncingTimerID = nil
                state.isClosing = false
                let stopObserving = Effect<Action>.merge(
                    .cancel(id: CancelID.snapshots),
                    .cancel(id: CancelID.pendingTimerRetry),
                    .cancel(id: CancelID.controls)
                )
                guard state.overlay != .end else { return stopObserving }
                return .merge(stopObserving, .cancel(id: CancelID.endDelay))
            }
        }
    }
}
