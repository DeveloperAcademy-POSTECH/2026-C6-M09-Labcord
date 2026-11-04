import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared
import UIKit

extension AppFeature {
    var watchReducer: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .watchTask:
                return .run { send in
                    let coordinator = await PhoneWatchExperimentCoordinator.shared
                    let events = await coordinator.events()
                    if let id = await coordinator.pendingStartID {
                        await send(.watchEvent(.started(id)))
                    }
                    for await event in events { await send(.watchEvent(event)) }
                }

            case let .watchEvent(.started(id)):
                state.watchPendingStartID = id
                return openWatchSession(&state)

            case let .watchSceneChanged(active):
                state.watchIsActive = active
                return active ? openWatchSession(&state) : .none

            case let .watchEvent(.command(command)):
                guard state.watchRequestID == nil,
                      let id = state.path.ids.last,
                      state.path[id: id, case: \.session]?.experimentID == command.experimentID
                else {
                    PhoneWatchExperimentCoordinator.shared.finish(
                        command.requestID, error: .phoneBusy
                    )
                    return .none
                }
                state.watchRequestID = command.requestID
                return .send(.path(.element(id: id, action: .session(.watchControl(command)))))

            case let .path(.element(_, action: .session(.watchControlFinished(id, error)))):
                state.watchRequestID = nil
                PhoneWatchExperimentCoordinator.shared.finish(id, error: error)
                return .none

            default:
                return .none
            }
        }
    }

    var watchContextReducer: some Reducer<State, Action> {
        Reduce { state, _ in
            let coordinator = PhoneWatchExperimentCoordinator.shared
            let sessionID = state.path.ids.last.flatMap {
                state.path[id: $0, case: \.session]?.experimentID
            }
            coordinator.visibleExperimentID = sessionID
            coordinator.isBusy = state.reviewSaving || state.home.list.isDeleting
                || state.home.list.pendingDeletion != nil
                || (!state.path.isEmpty && sessionID == nil)
            coordinator.refresh()
            return .none
        }
    }

    func finishWatchRequest(_ state: inout State) {
        guard let id = state.watchRequestID else { return }
        state.watchRequestID = nil
        PhoneWatchExperimentCoordinator.shared.finish(id)
    }

    func openWatchSession(_ state: inout State) -> Effect<Action> {
        guard state.watchIsActive, UIApplication.shared.applicationState == .active,
              let experimentID = state.watchPendingStartID else {
            return .none
        }
        if let id = state.path.ids.last,
           state.path[id: id, case: \.session]?.experimentID == experimentID {
            state.watchPendingStartID = nil
            PhoneWatchExperimentCoordinator.shared.didOpen(experimentID)
            return .none
        }
        guard state.path.isEmpty, !state.home.list.isDeleting,
              state.home.list.pendingDeletion == nil else { return .none }
        state.watchPendingStartID = nil
        PhoneWatchExperimentCoordinator.shared.didOpen(experimentID)
        state.path.append(.session(.init(experimentID: experimentID)))
        return .send(.home(.list(.cancelLoad)))
    }

}
