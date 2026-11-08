import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared
import UIKit

extension AppFeature {
    var watchReducer: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .timerNotificationTapped(id):
                return loadNotificationExperiment(&state, experimentID: id)

            case let .timerNotificationLoaded(id, token, entry):
                return openNotificationExperiment(
                    &state, experimentID: id, token: token, entry: entry
                )

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
                guard let id = state.path.ids.last,
                      let session = state.path[id: id, case: \.session],
                      session.experimentID == command.experimentID else {
                    PhoneWatchExperimentCoordinator.shared.finish(
                        command.requestID, error: .phoneBusy
                    )
                    return .none
                }
                let cancelsPhoto = command.operation == .cancelRecord
                    && session.watchMediaCommand?.operation == .takePhoto
                    && session.watchMediaCommand?.targetID == command.targetID
                    && command.targetID != nil
                guard state.watchRequestID == nil || cancelsPhoto else {
                    PhoneWatchExperimentCoordinator.shared.finish(
                        command.requestID, error: .phoneBusy
                    )
                    return .none
                }
                if !cancelsPhoto { state.watchRequestID = command.requestID }
                let action: ExperimentSessionFeature.Action =
                    [.pause, .complete].contains(command.operation)
                    ? .watchControl(command) : .watchRecordControl(command)
                return .send(.path(.element(id: id, action: .session(action))))

            case let .path(.element(_, action: .session(.watchControlFinished(id, error)))):
                PhoneWatchExperimentCoordinator.shared.finish(id, error: error)
                guard state.watchRequestID == id else { return .none }
                state.watchRequestID = nil
                return replayWatchNotification(&state)

            case let .path(.element(id, action: .session(.watchRecordResponse(response)))):
                guard let experimentID = state.path[id: id, case: \.session]?.experimentID else {
                    return .none
                }
                PhoneWatchExperimentCoordinator.shared.finishRecord(
                    response, experimentID: experimentID
                )
                if state.watchRequestID == response.requestID,
                   response.phase == .completed || response.phase == .failed
                    || response.record != nil {
                    state.watchRequestID = nil
                }
                if response.phase == .completed || response.phase == .failed {
                    return replayWatchNotification(&state)
                }
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

    func watchWorkPending(_ state: State) -> Bool {
        if state.watchRequestID != nil { return true }
        guard let id = state.path.ids.last,
              let session = state.path[id: id, case: \.session] else { return false }
        let capture = session.capture
        return capture.watchPhotoRequest != nil || capture.watchVideoRequest != nil
            || capture.watchReviewRequest != nil || capture.watchStopRequest != nil
    }

    func replayWatchNotification(_ state: inout State) -> Effect<Action> {
        guard !watchWorkPending(state),
              let id = state.watchNotificationGate.takeDeferredExperiment() else { return .none }
        return loadNotificationExperiment(&state, experimentID: id)
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
