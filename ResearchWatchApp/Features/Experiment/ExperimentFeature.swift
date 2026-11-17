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

    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var snapshot: WatchExperimentSnapshot?
        var isLoading = true
        var overlay: Overlay?
        var isClosing = false
        var closeResult: CloseResult?
        var errorMessage: String?
    }

    enum Action {
        case appeared
        case disappeared
        case snapshotReceived(WatchExperimentSnapshot)
        case snapshotRequestFailed
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
    }

    @Dependency(\.watchExperimentClient) private var watchExperimentClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                let experimentID = state.experimentID
                state.isLoading = state.snapshot == nil
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
                    .cancellable(id: CancelID.initialSnapshot, cancelInFlight: true)
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
                if snapshot.experiment.status == .paused {
                    state.closeResult = .paused
                    state.overlay = nil
                } else if snapshot.experiment.status == .completed {
                    state.closeResult = .completed
                    state.overlay = nil
                }
                return .none

            case .pauseTapped:
                guard state.overlay == nil, !state.isClosing else { return .none }
                state.overlay = .stop
                state.errorMessage = nil
                return .none

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
                    .cancel(id: CancelID.initialSnapshot)
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
