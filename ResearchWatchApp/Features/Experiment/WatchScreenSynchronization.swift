import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

extension WatchExperimentFeature.State {
    var blocksScreenTransition: Bool {
        pending != nil || pendingRecoveryFailed || !hasRestoredPending || screenRecoveryNeeded
            || isRequestingPermission || isPreparingInterruption || interruptionNeedsConfirmation
            || !recording.decisions.isEmpty || !recording.failedDecisions.isEmpty
            || recording.records.values.contains { recording.blocksNewCapture($0) }
    }

    var phoneScreenIsCurrent: Bool {
        isReachable && !screenRecoveryNeeded
            && phoneScreen.map { abs(currentTime.timeIntervalSince($0.recordedAt)) < 10 } == true
    }

    var showsMirroredRecording: Bool {
        guard let mirroredRecording, mirroredRecording.experimentID == selectedID,
              recording.focused == nil else { return false }
        if screen == .experiment { return true }
        return (screen == .timers || screen == .timerEditor)
            && mirroredRecording.phase != .saved && mirroredRecording.phase != .cancelled
    }

    var phoneRecordingBlocksCapture: Bool {
        guard let record = phoneScreen?.recording, record.origin == .phone else { return false }
        return record.phase != .saved && record.phase != .cancelled
    }
}

extension WatchExperimentFeature {
    func reduceScreenEvent(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .screenReceived(id, screen):
            guard state.isVisible, state.streamID == id else { return .none }
            return receiveScreen(screen, state: &state)
        case let .screenStreamEnded(id):
            guard state.streamID == id else { return .none }
            state.message = "화면 상태 수신이 중단됐어요. 다시 연결해주세요."
            return .none
        default: return .none
        }
    }

    func observeScreens(_ streamID: UUID) -> Effect<Action> {
        .run { [client] send in
            for await screen in await client.screens() {
                try Task.checkCancellation()
                await send(.screenReceived(streamID, screen))
            }
            guard !Task.isCancelled else { return }
            await send(.screenStreamEnded(streamID))
        }
        .cancellable(id: CancelID.screenStream, cancelInFlight: true)
    }

    func receiveScreen(_ screen: WatchScreenSnapshot, state: inout State) -> Effect<Action> {
        guard screen.isValid else { return .none }
        var contentChanged = true
        if let previous = state.phoneScreen {
            guard screen.revision > previous.revision
                    || (screen.revision == previous.revision && screen.hasSameContent(as: previous)
                        && screen.recordedAt > previous.recordedAt) else { return .none }
            contentChanged = !screen.hasSameContent(as: previous)
        }
        state.phoneScreen = screen
        state.currentTime = now
        let wasRecovering = state.screenRecoveryNeeded
        if abs(screen.recordedAt.timeIntervalSince(now)) < 10 {
            state.screenRecoveryNeeded = false
        }
        guard contentChanged || state.deferredScreen != nil || wasRecovering else { return .none }
        state.deferredScreen = screen
        if state.isRequestingPermission,
           screen.experimentID != state.selectedID || screen.stage != .permission {
            state.isRequestingPermission = false
            state.permissionRequestID = nil
            return .cancel(id: CancelID.permission)
        }
        return .none
    }

    func resumeScreenSynchronization(state: inout State) -> Effect<Action> {
        guard state.isVisible, state.streamID != nil, !state.blocksScreenTransition else {
            return .none
        }
        if let screen = state.deferredScreen, state.isReachable,
           abs(screen.recordedAt.timeIntervalSince(now)) < 10 {
            state.deferredScreen = nil
            let effect = applyScreen(screen, state: &state)
            return .merge(effect, applyQueuedNavigation(state: &state))
        }
        return applyQueuedNavigation(state: &state)
    }

    private func applyQueuedNavigation(state: inout State) -> Effect<Action> {
        guard !state.blocksScreenTransition else { return .none }
        guard let proposed = state.queuedNavigation, state.isReachable,
              state.queuedNavigationRequestID == nil else { return .none }
        state.queuedNavigation = nil
        let discardsTimerDraft = state.queuedNavigationDiscardsTimerDraft
        state.queuedNavigationDiscardsTimerDraft = false
        guard proposed.revision == state.phoneScreen?.revision else {
            state.message = "iPhone 화면이 바뀌었어요. 현재 화면에서 다시 선택해주세요."
            return .none
        }
        return navigate(proposed, discardTimerDraft: discardsTimerDraft, state: &state)
    }

    private func applyScreen(_ screen: WatchScreenSnapshot, state: inout State) -> Effect<Action> {
        let previousID = state.selectedID
        state.selectedID = screen.experimentID
        if previousID != screen.experimentID {
            state.authorization = nil
            state.startToken = nil
        }
        state.recording.focusedID = screen.recording.flatMap { active in
            guard active.origin == .watch, active.phase != .cancelled, active.phase != .saved,
                  let local = state.recording.records[active.id],
                  local.experimentID == screen.experimentID,
                  !local.isSettled, !local.isRecoverableVoiceFailure else {
                return nil
            }
            return active.id
        }
        state.mirroredRecording = screen.recording?.origin == .phone ? screen.recording : nil
        state.clearMessageUnlessInterruptionUnconfirmed()
        switch screen.destination {
        case .home:
            state.screen = .selection
            state.cleanupRequestID = nil
        case .registration:
            state.screen = .phoneRegistration
            state.cleanupRequestID = nil
        case .result:
            state.screen = .recordCleanup
        case .experiment:
            state.screen = watchScreen(for: screen.stage)
        }
        applyTimerDraft(screen, state: &state)
        var effects: [Effect<Action>] = []
        if screen.stage == .countdown, let endsAt = screen.countdownEndsAt {
            let seconds = max(0, Int(ceil(endsAt.timeIntervalSince(now))))
            state.screen = .countdown(seconds)
            if state.countdownID == nil,
               seconds > 0 || state.localCountdownEndsAt == endsAt {
                let id = uuid()
                state.countdownID = id
                effects.append(seconds > 0 ? countdown(token: id) : .send(.countdownTick(id)))
            }
            if state.localCountdownEndsAt != endsAt { state.localCountdownEndsAt = nil }
        } else {
            state.countdownID = nil
            state.localCountdownEndsAt = nil
            effects.append(.cancel(id: CancelID.countdown))
        }
        if previousID != state.selectedID || state.snapshot == nil {
            effects.append(request(state.selectedID == nil ? .list : .snapshot, state: &state))
        }
        return .merge(effects)
    }

    private func applyTimerDraft(_ screen: WatchScreenSnapshot, state: inout State) {
        guard screen.stage == .timerEditor, let seconds = screen.timerDraftSeconds,
              state.queuedNavigation?.revision != screen.revision else { return }
        state.timerHours = seconds / 3600
        state.timerMinutes = seconds / 60 % 60
        state.timerSeconds = seconds % 60
    }

    private func watchScreen(for stage: WatchScreenSnapshot.Stage?) -> Screen {
        switch stage {
        case .permission: .permission
        case .countdown: .countdown(0)
        case .pauseConfirmation: .confirmPause
        case .completionConfirmation: .confirmComplete
        case .resumeConfirmation: .confirmResume
        case .timers: .timers
        case .timerEditor: .timerEditor
        case .gestures: .gestures
        default: .experiment
        }
    }
}
