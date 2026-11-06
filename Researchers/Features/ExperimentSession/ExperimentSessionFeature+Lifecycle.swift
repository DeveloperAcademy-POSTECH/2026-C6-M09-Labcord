import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

enum SessionPhoneClose: Equatable {
    case pause
    case complete
}

enum SessionSetupFailure: Equatable {
    case permission(String)
    case camera(String)
}

extension ExperimentSessionFeature.State {
    var setupFailure: SessionSetupFailure? {
        if let issue = permissions.issue {
            return .permission(issue.message)
        }
        if cameraPreparationTimedOut {
            return .camera("카메라를 준비하지 못했어요. 다시 시도해주세요.")
        }
        if let message = capture.cameraErrorMessage, capture.previewConnector == nil {
            return .camera(message)
        }
        return nil
    }
}

extension ExperimentSessionFeature {
    private nonisolated enum CancelID: Hashable, Sendable {
        case cameraPreparation
    }

    func presentPause(state: inout State) -> Effect<Action> {
        state.isPausePresented = true
        guard !state.capture.isWatchPhotoScheduled else { return .none }
        return .send(.capture(.cancelPhotoGesture))
    }

    func reducePause(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .pauseTapped:
            return presentPause(state: &state)
        case .pause(.delegate(.resumeRequested)):
            state.isPausePresented = false
            return .none
        case .pause(.dismissHomeExitFailure):
            state.exitFailed = false
            return .none
        case .pause(.delegate(.stopRequested)):
            return pauseStopRequested(state: &state)
        case .pause(.delegate(.completed)):
            return .send(.stopCompleted)
        case .pause(.delegate(.completionFailed)):
            state.timer.isClosing = false
            return .send(.timer(.timerTick(now)))
        case .pause(.delegate(.returnHomeRequested)):
            return pauseReturnHomeRequested(state: &state)
        default:
            return sessionFollowUp(state: &state, action: action)
        }
    }

    func setupLeave(state: inout State) -> Effect<Action> {
        guard state.hasEnteredSession else {
            return .merge(
                .cancel(id: CancelID.cameraPreparation),
                .send(.permissions(.cancelRequest)),
                .send(.homeExitCompleted)
            )
        }
        guard state.canCloseSession,
              state.watchCommand == nil || state.watchClosingResources else {
            return .send(.homeExitCompleted)
        }
        return beginPhoneClose(.pause, state: &state)
    }

    func retryCameraPreparation(state: inout State) -> Effect<Action> {
        state.cameraPreparationTimedOut = false
        return .merge(
            .send(.capture(.cameraErrorDismissed)),
            .send(.capture(.cameraActivationRequested)),
            armCameraPreparationTimeout(state: &state)
        )
    }

    func cameraPreparationTimedOut(state: inout State) -> Effect<Action> {
        guard !state.isReady, state.capture.previewConnector == nil,
              state.permissions.camera.status == .authorized else { return .none }
        state.cameraPreparationTimedOut = true
        return .none
    }

    func sessionEntered(state: inout State) -> Effect<Action> {
        state.isEnteringSession = false
        state.hasEnteredSession = true
        state.sessionEntryFailed = false
        return .none
    }

    func sessionEntryFailed(state: inout State) -> Effect<Action> {
        state.isEnteringSession = false
        state.sessionEntryFailed = true
        state.detailLoadFailed = true
        return .none
    }

    func cameraAuthorized(state: inout State) -> Effect<Action> {
        .merge(
            .send(.capture(.cameraActivationRequested)),
            armCameraPreparationTimeout(state: &state),
            enterSessionIfReady(state: &state)
        )
    }

    func sessionFollowUp(state: inout State, action: Action) -> Effect<Action> {
        .merge(
            enterSessionIfReady(state: &state),
            phoneCloseFollowUp(state: &state, action: action)
        )
    }

    func sceneBackgrounded(state: inout State) -> Effect<Action> {
        var effects: [Effect<Action>] = []
        if state.capture.isPhotoCaptureScheduled, !state.capture.isCapturingPhoto,
           state.capture.capturedPhotoData == nil {
            effects.append(cancelBackgroundPhoto(state: &state))
        }
        if state.voice.phase == .recording || state.voice.phase == .starting {
            effects.append(.send(.voice(.stopAndSaveRequested)))
        }
        return .merge(effects)
    }

    func beginPhoneClose(_ kind: SessionPhoneClose, state: inout State) -> Effect<Action> {
        guard state.phoneClose == nil, state.canCloseSession else { return .none }
        state.phoneClose = kind
        state.voice.isSessionClosing = true
        state.capture.photo.isSessionClosing = true
        state.capture.video.isSessionClosing = true
        state.timer.isClosing = true
        switch kind {
        case .pause:
            state.isReturningHome = true
            state.exitFailed = false
        case .complete:
            state.isCompleting = true
            state.completionFailed = false
        }
        return .concatenate(
            .send(.capture(.cancelPhotoGesture)),
            .send(.phoneCloseProgress)
        )
    }

    func drainPhoneClose(state: inout State) -> Effect<Action> {
        guard let kind = state.phoneClose else { return .none }
        let saves = pendingPhoneCloseSaves(state)
        guard isPhoneCloseIdle(state) else { return .merge(saves) }
        state.phoneClose = nil
        switch kind {
        case .pause:
            return leaveSession(state: &state)
        case .complete:
            return completeEnteredSession(state: &state)
        }
    }

    func abandonPhoneClose(state: inout State, completion: Bool) -> Effect<Action> {
        state.phoneClose = nil
        state.isCompleting = false
        state.isReturningHome = false
        state.timer.isClosing = false
        state.voice.isSessionClosing = false
        state.capture.photo.isSessionClosing = false
        state.capture.video.isSessionClosing = false
        if completion {
            state.completionFailed = true
        } else {
            state.exitFailed = true
        }
        return .merge(
            .send(.timer(.timerTick(now))),
            finishWatchClose(state: &state, error: .storageFailed)
        )
    }
}

extension ExperimentSessionFeature {
    func armCameraPreparationTimeout(state: inout State) -> Effect<Action> {
        guard !state.isReady else { return .cancel(id: CancelID.cameraPreparation) }
        state.cameraPreparationTimedOut = false
        return .run { send in
            try await Task.sleep(for: .seconds(12))
            await send(.cameraPreparationTimedOut)
        }
        .cancellable(id: CancelID.cameraPreparation, cancelInFlight: true)
    }

    func enterSessionIfReady(state: inout State) -> Effect<Action> {
        guard state.isReady else { return .none }
        state.cameraPreparationTimedOut = false
        let cancel = Effect<Action>.cancel(id: CancelID.cameraPreparation)
        guard state.detail != nil, !state.hasEnteredSession, !state.isEnteringSession,
              !state.sessionEntryFailed else { return cancel }
        state.isEnteringSession = true
        let experimentID = state.experimentID
        let enteredAt = now
        return .merge(
            cancel,
            .run { send in
                do {
                    try await experimentClient.enterSession(experimentID, enteredAt)
                    await send(.sessionEntered)
                } catch {
                    await send(.sessionEntryFailed)
                }
            }
        )
    }

    func cancelBackgroundPhoto(state: inout State) -> Effect<Action> {
        guard let command = state.capture.watchPhotoRequest else {
            return .send(.capture(.cancelPhotoGesture))
        }
        let recordID = command.targetID ?? command.requestID
        state.capture.watchPhotoRequest = nil
        state.capture.photo.pendingWatchCaptureID = nil
        state.capture.rejectedWatchPhotoIDs.insert(recordID)
        let response = WatchExperimentResponse(
            requestID: command.requestID, phase: .failed, error: .cameraUnavailable,
            record: WatchRecordSnapshot(
                id: recordID, kind: .photo, phase: .cancelled,
                originalRetained: false, error: .cameraUnavailable
            )
        )
        return .merge(
            .send(.capture(.cancelPhotoGesture)),
            .send(.watchRecordResponse(response))
        )
    }

    func phoneCloseFollowUp(state: inout State, action: Action) -> Effect<Action> {
        guard let phoneClose = state.phoneClose else { return .none }
        if isPhoneCloseFailure(action, state: state) {
            return abandonPhoneClose(state: &state, completion: phoneClose == .complete)
        }
        guard advancesPhoneClose(action, state: state) else { return .none }
        return .send(.phoneCloseProgress)
    }

    func pendingPhoneCloseSaves(_ state: State) -> [Effect<Action>] {
        var effects: [Effect<Action>] = []
        if state.voice.phase != .hidden, !state.voice.isSaving {
            effects.append(.send(.voice(.stopAndSaveRequested)))
        }
        if state.capture.videoPhase != .idle, !state.capture.video.isSaving {
            effects.append(.send(.capture(.video(.stopAndSaveRequested))))
        }
        if state.capture.capturedPhotoData != nil, !state.capture.photo.isSaving {
            effects.append(.send(.capture(.photo(.saveRequested))))
        }
        return effects
    }

    func isPhoneCloseIdle(_ state: State) -> Bool {
        state.voice.phase == .hidden && !state.voice.isSaving
            && state.capture.videoPhase == .idle && !state.capture.video.isSaving
            && !state.capture.isCapturingPhoto && state.capture.capturedPhotoData == nil
            && !state.capture.photo.isSaving && state.timer.pendingSave == nil
    }

    func leaveSession(state: inout State) -> Effect<Action> {
        state.isReturningHome = true
        state.timer.isClosing = true
        let experimentID = state.experimentID
        let exitID = state.exitID ?? uuid()
        state.exitID = exitID
        let exitedAt = now
        let ownerID = state.capture.camera.ownerID
        let title = state.detail?.title ?? "실험"
        let runningTimers = state.timer.timerCollection.timers.filter {
            $0.status == .running && $0.remainingSeconds(at: exitedAt) > 0
        }
        return .run { send in
            do {
                try await experimentClient.leaveSession(experimentID, exitID, exitedAt)
            } catch {
                await send(.homeExitFailed)
                return
            }
            await scheduleRunningTimers(
                runningTimers, experimentID: experimentID, title: title
            )
            await cameraSessionClient.deactivate(ownerID)
            await send(.homeExitCompleted)
        }
    }

    func scheduleRunningTimers(
        _ runningTimers: [ExperimentTimer], experimentID: UUID, title: String
    ) async {
        guard !runningTimers.isEmpty,
              let status = try? await notificationPermissionClient.requestAccess() else { return }
        switch status {
        case .authorized, .provisional, .ephemeral:
            for timer in runningTimers {
                try? await timerCompletionNotificationClient.schedule(experimentID, title, timer)
            }
        case .notDetermined, .denied, .unknown:
            return
        }
    }

    func completeEnteredSession(state: inout State) -> Effect<Action> {
        state.isCompleting = true
        state.timer.isClosing = true
        let experimentID = state.experimentID
        let completedAt = now
        return .run { send in
            do {
                try await experimentClient.complete(experimentID, completedAt)
                await send(.stopCompleted)
            } catch {
                await send(.stopFailed)
            }
        }
    }
}

private extension ExperimentSessionFeature {
    func pauseStopRequested(state: inout State) -> Effect<Action> {
        guard state.canCloseSession else { return .send(.pause(.stopRejected)) }
        return beginPhoneClose(.complete, state: &state)
    }

    func pauseReturnHomeRequested(state: inout State) -> Effect<Action> {
        guard state.canCloseSession else { return .none }
        return .merge(
            .send(.pause(.homeExitStarted)),
            beginPhoneClose(.pause, state: &state)
        )
    }

    func isPhoneCloseFailure(_ action: Action, state: State) -> Bool {
        if isVoiceCloseFailure(action, state: state) { return true }
        switch action {
        case let .capture(.photo(.saveFailed(id, _))):
            return id == state.capture.photo.recordID
        case let .capture(.video(.saveFailed(id, _))):
            return id == state.capture.video.recordID
        case let .capture(.video(.recordingFailed(id, _))):
            return id == state.capture.video.sessionID
        case .capture(.photo(.captureFailed)), .timer(.timerSaveFailed):
            return true
        default:
            return false
        }
    }

    func isVoiceCloseFailure(_ action: Action, state: State) -> Bool {
        switch action {
        case let .voice(.stopped(id, recording)):
            guard id == state.voice.sessionID, recording == nil else { return false }
            return state.voice.errorMessage != nil
        case let .voice(.event(id, event)):
            guard id == state.voice.sessionID else { return false }
            if case .failed = event { return true }
            return false
        case let .voice(.saveFailed(id, _)):
            return id == state.voice.recordID
        case let .voice(.startFailed(id, _)), let .voice(.startPermissionFailed(id, _)):
            return id == state.voice.sessionID
        default:
            return false
        }
    }

    func advancesPhoneClose(_ action: Action, state: State) -> Bool {
        switch action {
        case .voice(.saved), .capture(.photo(.saved)), .capture(.photo(.captured)),
             .capture(.video(.saved)), .capture(.video(.recorded)), .timer(.timerSaved):
            return true
        case let .voice(.stopped(id, recording)):
            return id == state.voice.sessionID && recording != nil
        case let .voice(.event(id, event)):
            guard id == state.voice.sessionID else { return false }
            if case .failed = event { return false }
            return true
        default:
            return false
        }
    }
}
