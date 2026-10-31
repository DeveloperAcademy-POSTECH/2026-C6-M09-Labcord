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
        var timer: SessionTimerFeature.State
        
        var permissions = SessionPermissionsFeature.State()
        var voice = VoiceRecordingFeature.State()
        var capture = CameraCaptureFeature.State()
        var permissionRequestGeneration = 0
        var isReturningHome = false
        var exitID: UUID?
        var exitFailed = false
        var isCompleting = false
        var completionFailed = false

        init(experimentID: UUID) {
            self.experimentID = experimentID
            self.timer = SessionTimerFeature.State(experimentID: experimentID)
        }

        var isReady: Bool {
            permissions.camera.status == .authorized
                && permissions.microphoneStatus == .authorized
                && permissions.speechRecognitionStatus == .authorized
                && !permissions.isRequesting
                && capture.previewConnector != nil
        }

        var canCloseSession: Bool {
            timer.isConfigured && timer.pendingSave == nil
                && !isCompleting && !isReturningHome
        }
    }

    enum Action: Equatable {
        case loadDetail
        case detailLoaded(ExperimentSessionDetail)
        case timer(SessionTimerFeature.Action)
        case permissions(SessionPermissionsFeature.Action)
        case voice(VoiceRecordingFeature.Action)
        case capture(CameraCaptureFeature.Action)
        case voiceStartRequested
        case photoStartRequested
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

        Reduce { state, action in
            switch action {
            case .loadDetail:
                let experimentID = state.experimentID
                return .run { send in
                    guard let detail = try? await experimentClient.loadDetail(experimentID) else {
                        return
                    }
                    await send(.detailLoaded(detail))
                }

            case let .detailLoaded(detail):
                state.detail = detail
                return .send(
                    .timer(
                        .configure(
                            mode: detail.mode,
                            timerSeconds: detail.timerSeconds,
                            timers: detail.timers
                        )
                    )
                )

            case .appBecameActive:
                guard !state.isReady else { return .none }
                state.permissionRequestGeneration += 1
                return .none

            case .stopTapped:
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

            case .stopCompleted:
                state.isCompleting = false
                return .none

            case .stopFailed:
                state.isCompleting = false
                state.timer.isClosing = false
                state.completionFailed = true
                return .send(.timer(.timerTick(now)))

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
                return .run { send in
                    do {
                        try await experimentClient.leaveSession(experimentID, exitID, exitedAt)
                    } catch {
                        await send(.homeExitFailed)
                        return
                    }
                    await cameraSessionClient.cancelVideoRecording()
                    await speechRecordingClient.cancel()
                    await cameraSessionClient.deactivate(ownerID)
                    await send(.homeExitCompleted)
                }

            case .homeExitCompleted:
                return .none

            case .homeExitFailed:
                state.isReturningHome = false
                state.timer.isClosing = false
                state.exitFailed = true
                return .send(.timer(.timerTick(now)))

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
                guard state.voice.phase == .hidden,
                      state.capture.isCameraViewVisible,
                      !state.capture.isCapturingPhoto,
                      state.capture.capturedPhotoData == nil,
                      state.capture.videoPhase == .idle else { return .none }
                return .merge(
                    .send(.capture(.cancelPhotoGesture)),
                    .send(.voice(.prepareRequested))
                )

            case .photoStartRequested:
                guard state.voice.phase == .hidden else {
                    return .send(.capture(.cancelPhotoGesture))
                }
                return .send(.capture(.photoCaptureRequested))

            case .videoStartRequested:
                guard state.voice.phase == .hidden else { return .none }
                return .send(.capture(.videoRecordRequested))

            case .permissions, .voice, .capture, .timer:
                return .none
            }
        }
    }
}
