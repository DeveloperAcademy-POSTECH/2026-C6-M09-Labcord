import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared
import OSLog

private let cameraCaptureLog = Logger(subsystem: "Labcord", category: "Capture")

@Reducer
struct CameraCaptureFeature {
    @ObservableState
    struct State: Equatable {
        var camera = CameraFeature.State()
        var photo: PhotoFeature.State
        var video: VideoFeature.State
        var watchPhotoRequest: WatchExperimentCommand?
        var watchPhotoCancellationRequest: WatchExperimentCommand?
        var watchVideoCancellationRequest: WatchExperimentCommand?
        var watchVideoRequest: WatchExperimentCommand?
        var watchReviewRequest: WatchExperimentCommand?
        var watchStopRequest: WatchExperimentCommand?

        init(experimentID: UUID) {
            self.photo = PhotoFeature.State(experimentID: experimentID)
            self.video = VideoFeature.State(experimentID: experimentID)
        }

        var isCameraViewVisible: Bool { camera.isViewVisible }
        var previewConnector: CameraPreviewConnector? { camera.previewConnector }
        var isCameraSwitching: Bool { camera.isSwitching }
        var canRequestCameraCapture: Bool {
            camera.isViewVisible && !camera.isAppInBackground
                && camera.hasRequestedActivation && !camera.isSwitching
        }
        var isCameraReadyForCapture: Bool {
            canRequestCameraCapture && camera.previewConnector != nil
        }
        var canSwitchCamera: Bool {
            camera.previewConnector != nil && !camera.isSwitching &&
            photo.watchCaptureID == nil && !photo.isCapturing
                && photo.capturedData == nil && video.phase == .idle
        }
        var isPhotoCaptureScheduled: Bool { photo.isScheduled }
        var isCapturingPhoto: Bool { photo.isCapturing }
        var capturedPhotoData: Data? { photo.capturedData }
        var videoPhase: VideoFeature.Phase { video.phase }
        var cameraErrorMessage: String? {
            camera.errorMessage ?? photo.errorMessage ?? video.errorMessage
        }
    }

    enum Action: Equatable {
        case camera(CameraFeature.Action)
        case photo(PhotoFeature.Action)
        case video(VideoFeature.Action)
        case delegate(Delegate)
        case cameraViewAppeared
        case cameraViewDisappeared
        case cameraActivationRequested
        case cameraSwitchRequested
        case cameraErrorDismissed
        case photoGestureEvent(CameraHandEvent)
        case cancelPhotoGesture
        case voiceButtonTapped
        case photoButtonTapped
        case videoButtonTapped
        case videoRetakeAndRecordRequested
        case videoRecordRequested
        case photoRetakeAndCaptureRequested
        case photoCaptureRequested(UUID?)
        case watchCommand(WatchExperimentCommand)
        case watchCommandExpired(UUID)
    }

    enum Delegate: Equatable {
        case permissionAccessFailed(PermissionKind)
        case handEvent(CameraHandEvent)
        case voiceRequested
        case photoRequested(UUID?)
        case videoRequested
        case watchResponse(WatchExperimentResponse)
    }

    @Dependency(\.uuid) var uuid

    var body: some Reducer<State, Action> {
        Scope(state: \.camera, action: \.camera) {
            CameraFeature()
        }

        Scope(state: \.photo, action: \.photo) {
            PhotoFeature()
        }

        Scope(state: \.video, action: \.video) {
            VideoFeature()
        }

        Reduce { state, action in
            if let effect = reduceWatch(state: &state, action: action) { return effect }
            switch action {
            case .cameraViewAppeared:
                return .send(.camera(.viewAppeared))

            case .cameraViewDisappeared:
                let stopCamera: Effect<Action> = .merge(
                    .send(.camera(.viewDisappeared)), .send(.photo(.cancelGesture))
                )
                if case .preview = state.video.phase, state.video.requiresExternalConfirmation {
                    return stopCamera
                }
                return .merge(stopCamera, .send(.video(.cancelRequested)))

            case .cameraActivationRequested:
                return .send(.camera(.activationRequested))

            case .cameraSwitchRequested:
                guard state.canSwitchCamera else { return .none }
                return .merge(
                    .send(.photo(.cancelGesture)),
                    .send(.camera(.switchRequested))
                )

            case .cameraErrorDismissed:
                return .merge(
                    .send(.camera(.errorDismissed)),
                    .send(.photo(.errorDismissed)),
                    .send(.video(.errorDismissed))
                )

            case let .camera(.delegate(.permissionAccessFailed(kind))),
                 let .video(.delegate(.permissionAccessFailed(kind))):
                return .send(.delegate(.permissionAccessFailed(kind)))

            case let .camera(.delegate(.handEvent(event))):
                if case .oneFingerHeld = event {
                    return .merge(
                        .send(.photo(.disarmGesture)),
                        .send(.delegate(.handEvent(event)))
                    )
                }
                return .send(.delegate(.handEvent(event)))

            case let .photo(.delegate(.captureRequested(id))):
                return .send(.delegate(.photoRequested(id)))

            case let .photoGestureEvent(event):
                guard state.isCameraReadyForCapture,
                      state.video.phase == .idle else {
                    if case .fistHeld = event {
                        return .send(.photo(.disarmGesture))
                    }
                    return .none
                }
                return .send(.photo(.gestureEvent(event)))

            case .cancelPhotoGesture:
                if state.photo.isSessionClosing, state.photo.isScheduled,
                   let id = state.photo.watchCaptureID {
                    cameraCaptureLog.notice("Watch photo stopped id=\(id) reason=sessionClosing")
                    return .send(.photo(.captureFailed(id, "실험 종료로 촬영이 중단되었어요.")))
                }
                return .send(.photo(.cancelGesture))

            case .voiceButtonTapped:
                return .send(.delegate(.voiceRequested))

            case .photoButtonTapped:
                return .send(.delegate(.photoRequested(nil)))

            case .videoButtonTapped:
                return .send(.delegate(.videoRequested))

            case .videoRetakeAndRecordRequested:
                guard state.isCameraReadyForCapture,
                      !state.video.isSaving,
                      !state.video.isSessionClosing,
                      !state.photo.isCapturing,
                      !state.photo.isScheduled,
                      state.photo.capturedData == nil,
                      case .preview = state.video.phase else { return .none }
                return .concatenate(
                    .send(.video(.retakeRequested)),
                    .send(.videoRecordRequested)
                )

            case .videoRecordRequested:
                guard state.canRequestCameraCapture,
                      !state.photo.isCapturing,
                      !state.photo.isScheduled,
                      state.photo.capturedData == nil,
                      state.video.phase == .idle else { return .none }
                return .merge(
                    .send(.photo(.disarmGesture)),
                    .send(.video(.recordRequested))
                )

            case .photoRetakeAndCaptureRequested:
                guard state.isCameraReadyForCapture,
                      !state.photo.isSaving,
                      !state.photo.isSessionClosing,
                      state.photo.capturedData != nil,
                      state.video.phase == .idle else { return .none }
                return .concatenate(
                    .send(.photo(.retakeRequested)),
                    .send(.photo(.shortcutCaptureRequested(uuid())))
                )

            case let .photoCaptureRequested(id):
                guard state.canRequestCameraCapture, state.video.phase == .idle,
                      !state.photo.isSessionClosing else {
                    let requestID = id?.uuidString ?? "-"
                    let cameraReady = state.canRequestCameraCapture
                    let videoIdle = state.video.phase == .idle
                    let closing = state.photo.isSessionClosing
                    cameraCaptureLog.notice("""
                        photo blocked id=\(requestID, privacy: .public) \
                        cameraReady=\(cameraReady) \
                        videoIdle=\(videoIdle) \
                        closing=\(closing)
                        """)
                    guard let id, state.photo.isWatchCapture else { return .none }
                    return .send(.photo(.captureFailed(id, "카메라를 사용할 수 없어요.")))
                }
                return .send(.photo(.captureRequested(id)))

            case let .photo(.captured(id, _)):
                guard !state.camera.isViewVisible, state.photo.recordID == id,
                      state.photo.watchCaptureID == nil else { return .none }
                return .send(.photo(.discardHiddenLocalCapture(id)))

            case .camera, .photo, .video, .delegate, .watchCommand, .watchCommandExpired:
                return .none
            }
        }
    }
}
