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
                    if let id = try? await coordinator.validPendingStartID() {
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
                if !cancelsPhoto {
                    state.watchRequestID = command.requestID
                    switch command.operation {
                    case .pause:
                        state.watchCloseGate = .init(
                            requestID: command.requestID, sessionID: id, kind: .pause
                        )
                    case .complete:
                        state.watchCloseGate = .init(
                            requestID: command.requestID, sessionID: id, kind: .complete
                        )
                    default:
                        state.watchCloseGate = nil
                    }
                }
                let action: ExperimentSessionFeature.Action =
                    [.pause, .complete].contains(command.operation)
                    ? .watchControl(command) : .watchRecordControl(command)
                return .send(.path(.element(id: id, action: .session(action))))

            case let .path(.element(_, action: .session(.watchControlFinished(id, error)))):
                PhoneWatchExperimentCoordinator.shared.finish(id, error: error)
                guard state.watchRequestID == id else { return .none }
                state.watchRequestID = nil
                state.watchCloseGate = nil
                return .none

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
            let canResumeResult = state.path.ids.last.flatMap {
                state.path[id: $0, case: \.result]?.canRefreshExternalRecords
            } == true && !PhoneWatchAudioService.shared.hasUnsettledRecording()
            coordinator.isBusy = state.reviewSaving || state.home.list.isDeleting
                || state.home.list.pendingDeletion != nil
                || (!state.path.isEmpty && sessionID == nil && !canResumeResult)
            let current = coordinator.currentScreen
            var screen = screenSnapshot(state)
            if current.destination != screen.destination
                || current.experimentID != screen.experimentID || current.stage != screen.stage {
                PhoneWatchAudioService.shared.dismissFinishedScreenRecording()
                screen = screenSnapshot(state)
            }
            coordinator.updateScreen(screen)
            coordinator.refresh()
            return .none
        }
    }

    var watchCompletionNavigationReducer: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .path(.element(
                id: id, action: .session(.stopCompleted(attemptID, requestID))
            )):
                return finishSessionNavigation(
                    &state, sessionID: id, attemptID: attemptID,
                    requestID: requestID, kind: .complete
                )
            case let .path(.element(
                id: id, action: .session(.homeExitCompleted(attemptID, requestID))
            )):
                return finishSessionNavigation(
                    &state, sessionID: id, attemptID: attemptID,
                    requestID: requestID, kind: .pause
                )
            default:
                return .none
            }
        }
    }

    func finishSessionNavigation(
        _ state: inout State, sessionID: StackElementID, attemptID: UUID, requestID: UUID?,
        kind: WatchCloseCompletionGate<StackElementID>.Kind
    ) -> Effect<Action> {
        guard let session = state.path[id: sessionID, case: \.session] else { return .none }
        let acceptedID = kind == .complete
            ? session.lastStopCompletionID : session.homeExitAttempt.lastAcceptedID
        guard acceptedID == attemptID else { return .none }
        finishWatchRequest(&state, requestID: requestID, sessionID: sessionID, kind: kind)
        let navigation: Action = kind == .complete
            ? .showResult(sessionID) : .returnHome(sessionID)
        return .send(navigation)
    }

    func finishWatchRequest(
        _ state: inout State, requestID: UUID?, sessionID: StackElementID,
        kind: WatchCloseCompletionGate<StackElementID>.Kind
    ) {
        guard let gate = state.watchCloseGate,
              gate.matches(
                requestID: requestID, sessionID: sessionID, kind: kind
              ), state.watchRequestID == requestID else {
            return
        }
        state.watchRequestID = nil
        state.watchCloseGate = nil
        PhoneWatchExperimentCoordinator.shared.finish(gate.requestID)
    }

    func openWatchSession(_ state: inout State) -> Effect<Action> {
        guard state.watchIsActive, UIApplication.shared.applicationState == .active,
              let experimentID = state.watchPendingStartID else {
            return .none
        }
        guard (try? PhoneWatchExperimentCoordinator.shared.validPendingStartID()) == experimentID
        else {
            state.watchPendingStartID = nil
            return .none
        }
        if let id = state.path.ids.last,
           var session = state.path[id: id, case: \.session],
           session.experimentID == experimentID {
            let wasPreview = session.isRemotePreview
            session.isRemotePreview = false
            session.sharedStage = .active
            session.sharedCountdownEndsAt = nil
            if wasPreview { session.detail = nil }
            state.path[id: id, case: \.session] = session
            state.watchPendingStartID = nil
            PhoneWatchExperimentCoordinator.shared.didOpen(experimentID)
            return wasPreview
                ? .send(.path(.element(id: id, action: .session(.loadDetail)))) : .none
        }
        if let id = state.path.ids.last,
           let result = state.path[id: id, case: \.result],
           result.experimentID == experimentID, canLeaveCurrentScreen(state) {
            state.watchPendingStartID = nil
            PhoneWatchExperimentCoordinator.shared.didOpen(experimentID)
            state.path.removeAll()
            state.path.append(.session(.init(experimentID: experimentID)))
            return .send(.home(.list(.cancelLoad)))
        }
        guard state.path.isEmpty, !state.home.list.isDeleting,
              state.home.list.pendingDeletion == nil else { return .none }
        state.watchPendingStartID = nil
        PhoneWatchExperimentCoordinator.shared.didOpen(experimentID)
        state.path.append(.session(.init(experimentID: experimentID)))
        return .send(.home(.list(.cancelLoad)))
    }

}
