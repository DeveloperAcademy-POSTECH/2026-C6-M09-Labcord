import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

extension SessionTimerFeature {
    func removeUnlistedWatchTimer(
        _ command: WatchExperimentCommand, state: inout State
    ) -> Effect<Action>? {
        guard command.operation == .deleteTimer,
              !state.timerCollection.timers.contains(where: { $0.id == command.targetID })
        else { return nil }
        state.watchRequest = command
        state.isSaving = true
        return .run { send in
            do {
                try await experimentClient.applyWatchTimer(command)
                await send(.watchTimerRemovalFinished(command.requestID, nil))
            } catch {
                await send(.watchTimerRemovalFinished(
                    command.requestID, (error as? WatchExperimentError) ?? .storageFailed
                ))
            }
        }
    }

    func finishUnlistedWatchTimer(
        _ id: UUID, error: WatchExperimentError?, state: inout State
    ) -> Effect<Action> {
        guard state.watchRequest?.requestID == id else { return .none }
        state.watchRequest = nil
        state.isSaving = false
        return .send(.delegate(.init(
            requestID: id, phase: error == nil ? .completed : .failed, error: error
        )))
    }
}
