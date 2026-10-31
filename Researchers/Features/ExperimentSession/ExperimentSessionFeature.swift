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
        
        var permissions = SessionPermissionsFeature.State()
        var voice = VoiceRecordingFeature.State()
        var capture = CameraCaptureFeature.State()
        var permissionRequestGeneration = 0
        var isReturningHome = false
        var entryID: UUID?
        var hasEntered = false
        var isEntering = false
        var entryFailed = false
        var isCompleting = false
        var completionFailed = false

        var isReady: Bool {
            permissions.camera.status == .authorized
                && permissions.microphoneStatus == .authorized
                && permissions.speechRecognitionStatus == .authorized
                && !permissions.isRequesting
                && capture.previewConnector != nil
        }
    }

    enum Action: Equatable {
        case enterSession
        case entrySaved
        case entrySaveFailed
        case dismissEntryFailure
        case loadDetail
        case detailLoaded(ExperimentSessionDetail)
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

        Reduce { state, action in
            switch action {
            case .enterSession:
                guard !state.hasEntered, !state.isEntering, !state.isReturningHome else {
                    return .none
                }
                let entryID = state.entryID ?? uuid()
                state.entryID = entryID
                state.isEntering = true
                state.entryFailed = false
                let experimentID = state.experimentID
                let enteredAt = now
                return .run { send in
                    do {
                        try await experimentClient.markInProgress(experimentID, entryID, enteredAt)
                        await send(.entrySaved)
                    } catch {
                        await send(.entrySaveFailed)
                    }
                }

            case .entrySaved:
                state.isEntering = false
                state.hasEntered = true
                return .none

            case .entrySaveFailed:
                state.isEntering = false
                state.entryFailed = true
                return .none

            case .dismissEntryFailure:
                state.entryFailed = false
                return .none

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
                return .none

            case .appBecameActive:
                guard !state.isReady else { return .none }
                state.permissionRequestGeneration += 1
                return .none

            case .stopTapped:
                guard state.hasEntered, !state.isEntering,
                      !state.isCompleting, !state.isReturningHome else { return .none }
                state.isCompleting = true
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
                state.completionFailed = true
                return .none

            case .dismissStopFailure:
                state.completionFailed = false
                return .none

            case .returnHomeTapped:
                guard !state.isReturningHome, !state.isEntering,
                      !state.isCompleting else { return .none }
                state.isReturningHome = true
                let ownerID = state.capture.camera.ownerID
                return .run { send in
                    await cameraSessionClient.cancelVideoRecording()
                    await speechRecordingClient.cancel()
                    await cameraSessionClient.deactivate(ownerID)
                    await send(.homeExitCompleted)
                }

            case .homeExitCompleted:
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

            case .permissions, .voice, .capture:
                return .none
            }
        }
    }
}
