import ComposableArchitecture
import Foundation
import LabcordShared

extension WatchExperimentFeature {
    struct Authorization: Equatable {
        let operation: WatchExperimentCommand.Operation
        let experimentID: UUID
        let targetID: UUID?
        let seconds: Int?

        static func requiresToken(_ operation: WatchExperimentCommand.Operation) -> Bool {
            switch operation {
            case .start, .resume, .takePhoto, .startVideo: true
            default: false
            }
        }

        func permits(_ snapshot: WatchExperimentSnapshot?) -> Bool {
            guard let snapshot, snapshot.experiment.id == experimentID else { return false }
            switch operation {
            case .start: return snapshot.experiment.status == .ready
            case .resume: return snapshot.experiment.status == .paused
            case .takePhoto, .startVideo: return snapshot.experiment.status == .running
            default: return false
            }
        }
    }

    func handlePreparedStart(
        _ response: WatchExperimentResponse, state: inout State
    ) -> Effect<Action> {
        guard state.isVisible, state.streamID != nil, state.isReachable,
              let token = response.startToken,
              let authorization = state.authorization,
              state.selectedID == authorization.experimentID,
              authorization.permits(state.snapshot) else {
            return fail(.invalidPayload, state: &state, definitive: true)
        }
        state.authorization = nil

        return .concatenate(
            .merge(.cancel(id: CancelID.delivery), .cancel(id: CancelID.poll)),
            request(
                authorization.operation, targetID: authorization.targetID,
                seconds: authorization.seconds, token: token, state: &state
            )
        )
    }

    func countdown(token: UUID) -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: .seconds(1))
            await send(.countdownTick(token))
        }
        .cancellable(id: CancelID.countdown, cancelInFlight: true)
    }
}
