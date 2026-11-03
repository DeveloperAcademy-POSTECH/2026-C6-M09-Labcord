import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

@Reducer
struct ExperimentSessionFeature {
    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var detail: ExperimentSessionDetail?
        var isLoadingDetail = false
        var pendingVoiceStart = false
        var pendingVoiceGestureAt: Date?
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
        var completionRequestedAt: Date?
        var isCommittingCompletion = false
        var allowsAudioOnly = false
        var cameraStartupFailed = false

        init(experimentID: UUID) {
            self.experimentID = experimentID
            self.timer = SessionTimerFeature.State(experimentID: experimentID)
            self.voice = VoiceRecordingFeature.State(experimentID: experimentID)
            self.capture = CameraCaptureFeature.State(experimentID: experimentID)
        }

        var isReady: Bool {
            (allowsAudioOnly || (permissions.camera.status == .authorized
                && capture.previewConnector != nil))
                && permissions.microphoneStatus == .authorized
                && permissions.speechRecognitionStatus == .authorized
                && !permissions.isRequesting
        }

        var canContinueWithoutCamera: Bool {
            !permissions.isRequesting && (cameraStartupFailed
                || permissions.camera.status == .denied
                || permissions.camera.status == .restricted)
        }

        var canCloseSession: Bool {
            timer.isConfigured && timer.pendingSave == nil && !voice.isSaving
                && !isCompleting && !isReturningHome
        }
    }

    enum Action: Equatable {
        case loadDetail
        case detailLoaded(ExperimentSessionDetail)
        case detailLoadFailed
        case timer(SessionTimerFeature.Action)
        case permissions(SessionPermissionsFeature.Action)
        case voice(VoiceRecordingFeature.Action)
        case capture(CameraCaptureFeature.Action)
        case voiceStartRequested
        case photoStartRequested
        case videoStartRequested
        case appBecameActive
        case stopTapped
        case continueCompletion
        case continueWithoutCamera
        case retryCameraRequested
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

        completionReducer
        cameraRecoveryReducer

        Reduce { state, action in
            switch action {
            case .loadDetail:
                return loadDetail(state: &state)

            case let .detailLoaded(detail):
                return applyDetail(detail, state: &state)

            case .detailLoadFailed:
                state.isLoadingDetail = false
                guard state.pendingVoiceStart else { return .none }
                state.pendingVoiceStart = false
                state.pendingVoiceGestureAt = nil
                return .send(.voice(.detailLoadFailed))

            case .appBecameActive:
                guard !state.isReady else { return .none }
                state.permissionRequestGeneration += 1
                return .none

            case .stopTapped, .continueCompletion, .stopCompleted, .stopFailed,
                 .dismissStopFailure:
                return .none

            case .returnHomeTapped, .homeExitCompleted, .homeExitFailed,
                 .dismissHomeExitFailure:
                return .none

            case .permissions(.microphoneStatusUpdated(.authorized)):
                return .send(.capture(.prepareVideoRecordingRequested))

            case .permissions(.camera(.statusUpdated(.authorized))):
                guard !state.allowsAudioOnly else { return .none }
                return .send(.capture(.cameraActivationRequested))

            case .capture(.cameraViewDisappeared):
                return .merge(
                    .send(.permissions(.cancelRequest)),
                    .send(.voice(.closeRequested))
                )

            case let .capture(.delegate(.permissionAccessFailed(kind))):
                return .send(.permissions(.accessFailed(kind)))

            case .capture(.delegate(.voiceRequested)):
                state.pendingVoiceGestureAt = nil
                return .send(.voiceStartRequested)

            case .capture(.delegate(.photoRequested)):
                return .send(.photoStartRequested)

            case .capture(.delegate(.videoRequested)):
                return .send(.videoStartRequested)

            case let .capture(.delegate(.handEvent(event))):
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
                    case .hidden:
                        state.pendingVoiceGestureAt = detectedAt
                        return .send(.voiceStartRequested)
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
                guard !state.isCompleting, !state.isReturningHome,
                      state.voice.phase == .hidden,
                      state.capture.isCameraViewVisible,
                      !state.capture.isCapturingPhoto,
                      state.capture.capturedPhotoData == nil,
                      state.capture.videoPhase == .idle else { return .none }
                guard state.detail != nil else {
                    state.pendingVoiceStart = true
                    return .send(.loadDetail)
                }
                state.pendingVoiceGestureAt = nil
                return .merge(
                    .send(.capture(.cancelPhotoGesture)),
                    .send(.voice(.prepareRequested))
                )

            case .photoStartRequested:
                guard !state.isCompleting, !state.isReturningHome,
                      state.voice.phase == .hidden else {
                    return .send(.capture(.cancelPhotoGesture))
                }
                return .send(.capture(.photoCaptureRequested))

            case .videoStartRequested:
                guard !state.isCompleting, !state.isReturningHome,
                      state.voice.phase == .hidden else { return .none }
                return .send(.capture(.videoRecordRequested))

            case .permissions, .voice, .capture, .timer:
                return .none

            case .continueWithoutCamera, .retryCameraRequested:
                return .none
            }
        }
    }
}

private extension ExperimentSessionFeature {
    func loadDetail(state: inout State) -> Effect<Action> {
        guard !state.isLoadingDetail else { return .none }
        state.isLoadingDetail = true
        let experimentID = state.experimentID
        return .run { send in
            await timerCompletionNotificationClient.cancelForExperiment(experimentID)
            guard let detail = try? await experimentClient.loadDetail(experimentID) else {
                await send(.detailLoadFailed)
                return
            }
            await send(.detailLoaded(detail))
        }
    }

    func applyDetail(_ detail: ExperimentSessionDetail, state: inout State) -> Effect<Action> {
        state.isLoadingDetail = false
        state.detail = detail
        state.voice.contextualStrings = detail.speechContextualStrings
        let gestureIsFresh = state.pendingVoiceGestureAt.map {
            $0.timeIntervalSince(now) > -0.5
        } ?? true
        let shouldStartVoice = state.pendingVoiceStart && gestureIsFresh
        state.pendingVoiceStart = false
        state.pendingVoiceGestureAt = nil
        return .concatenate(
            .send(.timer(.configure(
                mode: detail.mode, timerSeconds: detail.timerSeconds, timers: detail.timers
            ))),
            shouldStartVoice ? .send(.voiceStartRequested) : .none
        )
    }
}
