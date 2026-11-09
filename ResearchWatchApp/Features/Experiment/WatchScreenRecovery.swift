import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

extension WatchExperimentFeature {
    func navigationNeedsRecovery(_ error: WatchExperimentError, state: State) -> Bool {
        state.pending?.command.operation == .navigate
            && [.resultUnknown, .deliveryTimeout, .notReachable].contains(error)
    }

    func recoverNavigation(state: inout State) -> Effect<Action> {
        guard let pending = state.pending, pending.command.operation == .navigate,
              let streamID = state.streamID else { return .none }
        guard clearRetainedRequest(pending.command, state: &state) else { return .none }
        state.pending = nil
        state.queuedNavigation = nil
        state.queuedNavigationRequestID = nil
        state.queuedNavigationDiscardsTimerDraft = false
        state.screenRecoveryNeeded = true
        state.message = "이동 결과를 확인하지 못했어요. 현재 iPhone 화면을 다시 확인해요."
        let query = WatchExperimentCommand(requestID: uuid(), operation: .screen)
        return .merge(
            .cancel(id: CancelID.request),
            .cancel(id: CancelID.delivery), .cancel(id: CancelID.poll),
            .run { [client] send in
                guard let response = try? await client.send(query),
                      response.phase == .completed, let screen = response.screen else { return }
                await send(.screenReceived(streamID, screen))
            }
        )
    }
}
