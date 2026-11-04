import ComposableArchitecture
import Foundation
import LabcordShared

extension WatchExperimentFeature {
    func activate(state: inout State) -> Effect<Action> {
        guard !state.isVisible else { return .none }
        state.isVisible = true
        let streamID = uuid()
        state.streamID = streamID
        return .merge(
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
            return .none
        case let .streamEnded(id):
            guard state.streamID == id else { return .none }
            state.isVisible = false
            state.message = "상태 수신이 중단됐어요. 다시 연결해주세요."
            return .cancel(id: CancelID.connection)
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

    func accept(_ snapshot: WatchExperimentSnapshot, state: inout State) {
        let id = snapshot.experiment.id
        guard id == state.selectedID else { return }
        guard WatchPresentationRules.accepts(
            revision: snapshot.revision, previous: state.snapshots[id]?.revision
        ) else { return }
        state.snapshots[id] = snapshot
        if let index = state.experiments.firstIndex(where: { $0.id == id }) {
            state.experiments[index] = snapshot.experiment
        }
    }
}

enum WatchPresentationRules {
    static func accepts(revision: UInt64, previous: UInt64?) -> Bool {
        previous.map { revision > $0 } ?? true
    }

    static func time(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
}
