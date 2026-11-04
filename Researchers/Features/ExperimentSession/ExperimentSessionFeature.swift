import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

@Reducer
struct ExperimentSessionFeature {
    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var watchCommand: WatchExperimentCommand?
        var watchCameraWasVisible = false
        var detail: ExperimentSessionDetail?
        var isLoadingDetail = false
        var detailLoadFailed = false
        var timer: SessionTimerFeature.State

        var permissions = SessionPermissionsFeature.State()
        var voice: VoiceRecordingFeature.State
        var capture: CameraCaptureFeature.State
        var permissionRequestGeneration = 0
        var isReturningHome = false
        var exitID: UUID?
        var exitFailed = false
        var isCompleting = false
        var completionFailed = false

        init(experimentID: UUID) {
            self.experimentID = experimentID
            self.timer = SessionTimerFeature.State(experimentID: experimentID)
            self.voice = VoiceRecordingFeature.State(experimentID: experimentID)
            self.capture = CameraCaptureFeature.State(experimentID: experimentID)
        }

        var isReady: Bool {
            permissions.camera.status == .authorized
                && permissions.microphoneStatus == .authorized
                && permissions.speechRecognitionStatus == .authorized
                && !permissions.isRequesting
                && capture.previewConnector != nil
        }

        var canCloseSession: Bool {
            timer.isConfigured && timer.pendingSave == nil && !voice.isSaving
                && !isCompleting && !isReturningHome
        }
    }

    enum Action: Equatable {
        case watchControl(WatchExperimentCommand)
        case watchResourcesReleased
        case watchControlFinished(UUID, WatchExperimentError?)
        case loadDetail
        case detailLoaded(ExperimentSessionDetail)
        case detailLoadingFailed
        case dismissDetailLoadFailure
        case timer(SessionTimerFeature.Action)
        case permissions(SessionPermissionsFeature.Action)
        case voice(VoiceRecordingFeature.Action)
        case capture(CameraCaptureFeature.Action)
        case voiceStartRequested
        case photoStartRequested(UUID?)
        case videoStartRequested
        case appBecameActive
        case stopTapped
        case stopCompleted
        case stopFailed
        case dismissStopFailure
        case returnHomeTapped
        case homeExitCompleted
        case homeExitFailed
        case dismissHomeExitFailure
    }

    @Dependency(\.experimentClient) var experimentClient
    @Dependency(\.date.now) var now
    @Dependency(\.uuid) var uuid
    @Dependency(\.cameraSessionClient) var cameraSessionClient
    @Dependency(\.speechRecordingClient) var speechRecordingClient
    @Dependency(\.notificationPermissionClient) var notificationPermissionClient
    @Dependency(\.timerCompletionNotificationClient) var timerCompletionNotificationClient

    var body: some Reducer<State, Action> {
        watchReducer
        Scope(state: \.permissions, action: \.permissions) {
            SessionPermissionsFeature()
        }

        Scope(state: \.voice, action: \.voice) {
            VoiceRecordingFeature()
        }

        Scope(state: \.capture, action: \.capture) {
            CameraCaptureFeature()
        }

        Scope(state: \.timer, action: \.timer) {
            SessionTimerFeature()
        }

        Reduce { state, action in
            switch action {
            case .watchControl, .watchResourcesReleased, .watchControlFinished:
                return .none

            case .loadDetail:
                return loadDetail(state: &state)

            case let .detailLoaded(detail):
                state.isLoadingDetail = false
                state.detail = detail
                state.voice.contextualStrings = detail.speechContextualStrings
                return .send(
                    .timer(
                        .configure(
                            mode: detail.mode,
                            timerSeconds: detail.timerSeconds,
                            timers: detail.timers
                        )
                    )
                )

            case .detailLoadingFailed:
                state.isLoadingDetail = false
                state.detailLoadFailed = true
                return .none

            case .dismissDetailLoadFailure:
                state.detailLoadFailed = false
                return .none

            case .appBecameActive:
                guard !state.isReady else { return .none }
                state.permissionRequestGeneration += 1
                return .none

            case .stopTapped:
                return completeSession(state: &state)

            case .stopCompleted:
                state.isCompleting = false
                state.watchCommand = nil
                return .none

            case .stopFailed:
                state.isCompleting = false
                state.timer.isClosing = false
                state.completionFailed = true
                return .merge(
                    .send(.timer(.timerTick(now))),
                    finishWatchClose(state: &state, error: .storageFailed)
                )

            case .dismissStopFailure:
                state.completionFailed = false
                return .none

            case .returnHomeTapped:
                guard state.canCloseSession else { return .none }
                state.isReturningHome = true
                state.timer.isClosing = true
                state.exitFailed = false
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
                    if !runningTimers.isEmpty,
                       let status = try? await notificationPermissionClient.requestAccess() {
                        switch status {
                        case .authorized, .provisional, .ephemeral:
                            for timer in runningTimers {
                                try? await timerCompletionNotificationClient.schedule(
                                    experimentID, title, timer
                                )
                            }
                        case .notDetermined, .denied, .unknown:
                            break
                        }
                    }
                    await send(.voice(.closeRequested))
                    await cameraSessionClient.cancelVideoRecording()
                    await speechRecordingClient.cancel()
                    await cameraSessionClient.deactivate(ownerID)
                    await send(.homeExitCompleted)
                }

            case .homeExitCompleted:
                state.watchCommand = nil
                return .none

            case .homeExitFailed:
                state.isReturningHome = false
                state.timer.isClosing = false
                state.exitFailed = true
                return .merge(
                    .send(.timer(.timerTick(now))),
                    finishWatchClose(state: &state, error: .storageFailed)
                )

            case .dismissHomeExitFailure:
                state.exitFailed = false
                return .none

            case .permissions(.microphoneStatusUpdated(.authorized)):
                return .send(.capture(.prepareVideoRecordingRequested))

            case .permissions(.camera(.statusUpdated(.authorized))):
                return .send(.capture(.cameraActivationRequested))

            case .capture(.cameraViewDisappeared):
                return .merge(
                    .send(.permissions(.cancelRequest)),
                    .send(.voice(.closeRequested))
                )

            case let .capture(.delegate(.permissionAccessFailed(kind))):
                return .send(.permissions(.accessFailed(kind)))

            case let .voice(.startPermissionFailed(id, kind)):
                guard id == state.voice.sessionID else { return .none }
                return .send(.permissions(.accessFailed(kind)))

            case .capture(.delegate(.voiceRequested)):
                return .send(.voiceStartRequested)

            case let .capture(.delegate(.photoRequested(id))):
                return .send(.photoStartRequested(id))

            case .capture(.delegate(.videoRequested)):
                return .send(.videoStartRequested)

            case let .capture(.delegate(.handEvent(event))):
                guard state.watchCommand == nil else { return .none }
                switch event {
                case .openHandHeld:
                    guard state.voice.phase == .hidden else { return .none }
                    return .send(.capture(.photoGestureEvent(event)))

                case .fistHeld:
                    guard state.voice.phase == .hidden else {
                        return .send(.capture(.cancelPhotoGesture))
                    }
                    return .send(.capture(.photoGestureEvent(event)))

                case let .oneFingerHeld(detectedAt):
                    guard state.capture.isCameraViewVisible,
                          state.capture.previewConnector != nil,
                          !state.capture.isCameraSwitching,
                          !state.capture.isPhotoCaptureScheduled,
                          !state.capture.isCapturingPhoto,
                          state.capture.capturedPhotoData == nil,
                          state.capture.videoPhase == .idle,
                          detectedAt.timeIntervalSinceNow > -0.5 else { return .none }
                    switch state.voice.phase {
                    case .hidden: return .send(.voiceStartRequested)
                    case .recording: return .send(.voice(.stopRequested))
                    case .starting, .stopping, .finished: return .none
                    }

                case let .threeFingersHeld(detectedAt):
                    guard !state.capture.isPhotoCaptureScheduled,
                          !state.capture.isCapturingPhoto,
                          detectedAt.timeIntervalSinceNow > -0.5 else { return .none }
                    return .send(.videoStartRequested)
                }

            case .voiceStartRequested:
                return prepareVoiceRecording(state: &state)

            case let .photoStartRequested(id):
                guard state.watchCommand == nil else { return .none }
                guard state.voice.phase == .hidden else {
                    return .send(.capture(.cancelPhotoGesture))
                }
                return .send(.capture(.photoCaptureRequested(id)))

            case .videoStartRequested:
                guard state.watchCommand == nil, state.voice.phase == .hidden else { return .none }
                return .send(.capture(.videoRecordRequested))

            case .permissions, .voice, .capture, .timer:
                return .none
            }
        }
    }
}

private extension ExperimentSessionFeature {
    func completeSession(state: inout State) -> Effect<Action> {
        guard state.canCloseSession else { return .none }
        state.isCompleting = true
        state.timer.isClosing = true
        state.completionFailed = false
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

    func loadDetail(state: inout State) -> Effect<Action> {
        guard state.detail == nil, !state.isLoadingDetail else { return .none }
        state.isLoadingDetail = true
        state.detailLoadFailed = false
        let experimentID = state.experimentID
        return .run { send in
            await timerCompletionNotificationClient.cancelForExperiment(experimentID)
            guard let detail = try? await experimentClient.loadDetail(experimentID) else {
                await send(.detailLoadingFailed)
                return
            }
            await send(.detailLoaded(detail))
        }
    }

    func prepareVoiceRecording(state: inout State) -> Effect<Action> {
        guard state.watchCommand == nil else { return .none }
        guard state.detail != nil else {
            if state.isLoadingDetail {
                state.voice.errorMessage = "실험 정보를 불러오고 있어요. 잠시 후 다시 시도해 주세요."
            } else {
                state.detailLoadFailed = true
            }
            return .none
        }
        guard state.voice.phase == .hidden,
              state.capture.isCameraViewVisible,
              !state.capture.isCapturingPhoto,
              state.capture.capturedPhotoData == nil,
              state.capture.videoPhase == .idle else { return .none }
        return .merge(
            .send(.capture(.cancelPhotoGesture)),
            .send(.voice(.prepareRequested))
        )
    }
}
