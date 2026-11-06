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
        var watchMediaCommand: WatchExperimentCommand?
        var watchClosingResources = false
        var watchCameraWasVisible = false
        var detail: ExperimentSessionDetail?
        var isLoadingDetail = false
        var detailLoadFailed = false
        var timer: SessionTimerFeature.State

        var permissions = SessionPermissionsFeature.State()
        var voice: VoiceRecordingFeature.State
        var capture: CameraCaptureFeature.State
        var pause: ExperimentPauseFeature.State
        var permissionRequestGeneration = 0
        var isPausePresented = false
        var isReturningHome = false
        var exitID: UUID?
        var exitFailed = false
        var isCompleting = false
        var completionFailed = false
        var hasEnteredSession = false
        var isEnteringSession = false
        var sessionEntryFailed = false
        var cameraPreparationTimedOut = false
        var phoneClose: SessionPhoneClose?

        init(experimentID: UUID) {
            self.experimentID = experimentID
            self.timer = SessionTimerFeature.State(experimentID: experimentID)
            self.voice = VoiceRecordingFeature.State(experimentID: experimentID)
            self.capture = CameraCaptureFeature.State(experimentID: experimentID)
            self.pause = ExperimentPauseFeature.State(experimentID: experimentID)
        }

        var isReady: Bool {
            permissions.camera.status == .authorized
                && permissions.microphoneStatus == .authorized
                && permissions.speechRecognitionStatus == .authorized
                && !permissions.isRequesting
                && capture.previewConnector != nil
        }

        var canCloseSession: Bool {
            timer.isConfigured && timer.pendingSave == nil && !timer.isClosing && !voice.isSaving
                && !pause.isCompleting && !isReturningHome
        }
    }

    enum Action: Equatable {
        case watchRecordControl(WatchExperimentCommand)
        case watchRecordResponse(WatchExperimentResponse)
        case watchDrainProgress
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
        case pause(ExperimentPauseFeature.Action)
        case voiceStartRequested
        case photoStartRequested(UUID?)
        case videoStartRequested
        case appBecameActive
        case sceneBackgrounded
        case setupLeaveTapped
        case setupRetryCameraTapped
        case cameraPreparationTimedOut
        case sessionEntered
        case sessionEntryFailed
        case phoneCloseProgress
        case pauseTapped
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

        Scope(state: \.pause, action: \.pause) {
            ExperimentPauseFeature()
        }

        watchCompletionReducer

        Reduce { state, action in
            switch action {
            case .watchControl, .watchResourcesReleased, .watchControlFinished,
                 .watchRecordControl, .watchRecordResponse, .watchDrainProgress:
                return .none

            case .loadDetail:
                return loadDetail(state: &state)

            case let .detailLoaded(detail):
                return .merge(
                    configureSessionDetail(detail, state: &state),
                    enterSessionIfReady(state: &state)
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

            case .sceneBackgrounded:
                return sceneBackgrounded(state: &state)

            case .setupLeaveTapped:
                return setupLeave(state: &state)

            case .setupRetryCameraTapped:
                return retryCameraPreparation(state: &state)

            case .cameraPreparationTimedOut:
                return cameraPreparationTimedOut(state: &state)

            case .sessionEntered:
                return sessionEntered(state: &state)

            case .sessionEntryFailed:
                return sessionEntryFailed(state: &state)

            case .phoneCloseProgress:
                return drainPhoneClose(state: &state)

            case .pauseTapped, .pause:
                return reducePause(state: &state, action: action)

            case .stopTapped:
                guard state.watchCommand == nil || state.watchClosingResources else {
                    return .none
                }
                return beginPhoneClose(.complete, state: &state)

            case .returnHomeTapped:
                guard state.watchCommand == nil || state.watchClosingResources else {
                    return .none
                }
                return beginPhoneClose(.pause, state: &state)

            case .stopCompleted, .homeExitCompleted:
                state.isCompleting = false
                state.watchCommand = nil
                state.watchClosingResources = false
                return .none

            case .stopFailed:
                state.pause.isCompleting = false
                state.pause.isEndTriggered = false
                return abandonPhoneClose(state: &state, completion: true)

            case .dismissStopFailure:
                state.completionFailed = false
                return .none

            case .homeExitFailed:
                return .merge(
                    abandonPhoneClose(state: &state, completion: false),
                    .send(.pause(.homeExitFailed))
                )

            case .dismissHomeExitFailure:
                state.exitFailed = false
                state.pause.exitFailed = false
                return .none

            case .permissions(.microphoneStatusUpdated(.authorized)):
                return .merge(
                    .send(.capture(.prepareVideoRecordingRequested)),
                    enterSessionIfReady(state: &state)
                )

            case .permissions(.camera(.statusUpdated(.authorized))):
                return cameraAuthorized(state: &state)

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
                guard !state.isPausePresented else { return .none }
                return .send(.photoStartRequested(id))

            case .capture(.delegate(.videoRequested)):
                return .send(.videoStartRequested)

            case let .capture(.delegate(.handEvent(event))):
                guard state.watchCommand == nil, !state.isPausePresented else { return .none }
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
                guard !state.isPausePresented else { return .none }
                return prepareVoiceRecording(state: &state)

            case let .photoStartRequested(id):
                guard !state.isPausePresented else { return .none }
                return startPhoto(id, state: &state)

            case .videoStartRequested:
                guard !state.isPausePresented, state.watchCommand == nil,
                      state.voice.phase == .hidden else { return .none }
                return .send(.capture(.videoRecordRequested))

            case .permissions, .voice, .capture, .timer:
                return sessionFollowUp(state: &state, action: action)
            }
        }
    }
}
