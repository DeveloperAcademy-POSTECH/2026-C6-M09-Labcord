import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

extension AppFeature {
    var screenNavigationReducer: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .path(.element(id: id, action: .session(.cancelRemotePreview))):
                guard let session = state.path[id: id, case: \.session],
                      session.isRemotePreview, !session.hasUnsettledLocalMedia,
                      !session.timer.hasUnsavedDraft, state.watchRequestID == nil,
                      !PhoneWatchAudioService.shared.hasUnsettledRecording() else {
                    return .none
                }
                state.watchPendingStartID = nil
                state.path.removeAll()
                return .send(.home(.list(.load)))
            case let .watchEvent(.navigation(command)):
                return receiveNavigation(command, state: &state)
            case let .screenNavigationLoaded(id, detail, error):
                return finishNavigation(id, detail: detail, error: error, state: &state)
            case let .watchEvent(.recordChanged(experimentID)):
                guard let id = state.path.ids.last,
                      state.path[id: id, case: \.result]?.experimentID == experimentID else {
                    return .none
                }
                return .send(.path(.element(id: id, action: .result(.externalRecordsChanged))))
            default:
                return .none
            }
        }
    }

    func canLeaveCurrentScreen(_ state: State) -> Bool {
        Self.canLeaveLocalScreen(state)
            && !PhoneWatchAudioService.shared.hasUnsettledRecording()
    }

    static func canLeaveLocalScreen(_ state: State) -> Bool {
        guard !state.reviewSaving, !state.home.list.isDeleting,
              state.home.list.pendingDeletion == nil else { return false }
        guard let id = state.path.ids.last else { return true }
        if let session = state.path[id: id, case: \.session] {
            return !session.hasUnsettledScreenWork && !session.timer.hasUnsavedDraft
        }
        if let result = state.path[id: id, case: \.result] {
            return result.canRefreshExternalRecords
        }
        return false
    }

    func screenSnapshot(_ state: State) -> WatchScreenSnapshot {
        guard let id = state.path.ids.last else { return .init(destination: .home) }
        if state.path[id: id, case: \.gestureGuide] != nil
            || state.path[id: id, case: \.gesturePractice] != nil {
            return .init(destination: .home)
        }
        if let session = state.path[id: id, case: \.session] {
            let remote = PhoneWatchAudioService.shared.screenRecording
            return session.screenSnapshot(
                watchRecording: remote?.experimentID == session.experimentID ? remote : nil
            )
        }
        if let result = state.path[id: id, case: \.result] {
            return .init(
                destination: .result, experimentID: result.experimentID,
                stage: result.isResumeConfirmationPresented ? .resumeConfirmation : .completed
            )
        }
        return .init(destination: .registration)
    }

    func canNavigate(_ command: WatchExperimentCommand, state: State) -> Bool {
        guard let screen = command.screen else { return false }
        guard let id = state.path.ids.last,
              var session = state.path[id: id, case: \.session],
              screen.destination == .experiment, screen.experimentID == session.experimentID,
              session.timer.isEditorPresented,
              screen.stage == .timerEditor || (command.discardTimerDraft == true
                  && (screen.stage == .timers || screen.stage == .active)) else {
            return canLeaveCurrentScreen(state)
        }
        var draftState = state
        session.timer.initialDraftSeconds = session.timer.draftSeconds
        draftState.path[id: id, case: \.session] = session
        return canLeaveCurrentScreen(draftState)
    }

    private func receiveNavigation(
        _ command: WatchExperimentCommand, state: inout State
    ) -> Effect<Action> {
        guard let screen = command.screen, screen.isValid,
              screen.destination != .registration else {
            return rejectNavigation(command.requestID, error: .invalidPayload)
        }
        guard screen.revision == PhoneWatchExperimentCoordinator.shared.currentScreen.revision
        else {
            return rejectNavigation(command.requestID, error: .staleRevision)
        }
        guard state.screenNavigation == nil, state.watchRequestID == nil,
              canNavigate(command, state: state) else {
            return rejectNavigation(command.requestID, error: .phoneBusy)
        }
        if screen.destination == .home {
            state.watchPendingStartID = nil
            state.path.removeAll()
            completeNavigation(command.requestID, state: state)
            return .send(.home(.list(.load)))
        }
        guard let experimentID = screen.experimentID else {
            return rejectNavigation(command.requestID, error: .invalidPayload)
        }
        state.screenNavigation = command
        state.watchRequestID = command.requestID
        return .run { send in
            do {
                let detail = try await experimentClient.watchState(experimentID)
                await send(.screenNavigationLoaded(command.requestID, detail, nil))
            } catch {
                await send(.screenNavigationLoaded(command.requestID, nil, .storageFailed))
            }
        }
    }

    private func finishNavigation(
        _ requestID: UUID, detail: WatchExperimentState?, error: WatchExperimentError?,
        state: inout State
    ) -> Effect<Action> {
        guard let command = state.screenNavigation, command.requestID == requestID,
              let screen = command.screen else { return .none }
        state.screenNavigation = nil
        if state.watchRequestID == requestID { state.watchRequestID = nil }
        guard screen.revision == PhoneWatchExperimentCoordinator.shared.currentScreen.revision
        else {
            return rejectNavigation(requestID, error: .staleRevision)
        }
        guard canNavigate(command, state: state) else {
            return rejectNavigation(requestID, error: .phoneBusy)
        }
        guard error == nil, let detail, detail.experiment.id == screen.experimentID else {
            return rejectNavigation(requestID, error: error ?? .experimentNotFound)
        }
        guard screen.destination != .result || detail.experiment.status == .completed else {
            return rejectNavigation(requestID, error: .invalidState)
        }
        state.watchPendingStartID = nil
        if detail.experiment.status == .completed {
            if let id = state.path.ids.last,
               state.path[id: id, case: \.result]?.experimentID == detail.experiment.id {
                state.path[id: id, case: \.result]?.isResumeConfirmationPresented =
                    screen.stage == .resumeConfirmation
                completeNavigation(requestID, state: state)
                return .none
            }
            state.path.removeAll()
            var result = ExperimentResultFeature.State(
                experimentID: detail.experiment.id, isOpenedFromHome: true
            )
            result.isResumeConfirmationPresented = screen.stage == .resumeConfirmation
            state.path.append(.result(result))
        } else {
            showSynchronizedSession(command, detail: detail, state: &state)
        }
        completeNavigation(requestID, state: state)
        return .send(.home(.list(.cancelLoad)))
    }

    private func showSynchronizedSession(
        _ command: WatchExperimentCommand, detail: WatchExperimentState, state: inout State
    ) {
        guard let screen = command.screen else { return }
        if let id = state.path.ids.last,
           var session = state.path[id: id, case: \.session],
           session.experimentID == detail.experiment.id {
            if command.discardTimerDraft == true {
                session.timer.draftSeconds = session.timer.initialDraftSeconds
            }
            session.applyScreen(screen, status: detail.experiment.status)
            state.path[id: id, case: \.session] = session
            return
        }
        var session = ExperimentSessionFeature.State(experimentID: detail.experiment.id)
        session.applyScreen(screen, status: detail.experiment.status)
        state.path.removeAll()
        state.path.append(.session(session))
    }

    private func completeNavigation(_ requestID: UUID, state: State) {
        let coordinator = PhoneWatchExperimentCoordinator.shared
        PhoneWatchAudioService.shared.dismissFinishedScreenRecording()
        coordinator.updateScreen(screenSnapshot(state))
        coordinator.finish(requestID, error: coordinator.lastScreenError)
    }

    private func rejectNavigation(
        _ requestID: UUID, error: WatchExperimentError
    ) -> Effect<Action> {
        PhoneWatchExperimentCoordinator.shared.finish(requestID, error: error)
        return .none
    }
}
