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
    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var snapshot: WatchExperimentSnapshot?
        var isLoading = true
    }

    enum Action {
        case appeared
        case disappeared
        case snapshotReceived(WatchExperimentSnapshot)
        case snapshotRequestFailed
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case snapshots
        case initialSnapshot
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
                return .none

            case .snapshotRequestFailed:
                if state.snapshot == nil { state.isLoading = false }
                return .none

            case .disappeared:
                return .merge(
                    .cancel(id: CancelID.snapshots),
                    .cancel(id: CancelID.initialSnapshot)
                )
            }
        }
    }
}
