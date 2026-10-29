import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

@Reducer
struct CameraCaptureFeature {
    @ObservableState
    struct State: Equatable {
        var camera = CameraFeature.State()
        var photo = PhotoFeature.State()
        var video = VideoFeature.State()

        var isCameraViewVisible: Bool { camera.isViewVisible }
        var previewConnector: CameraPreviewConnector? { camera.previewConnector }
        var isCameraSwitching: Bool { camera.isSwitching }
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
        case prepareVideoRecordingRequested
        case cameraSwitchRequested
        case cameraErrorDismissed
        case photoGestureEvent(CameraHandEvent)
        case cancelPhotoGesture
        case voiceButtonTapped
        case photoButtonTapped
        case videoButtonTapped
        case videoRecordRequested
        case videoRetakeRequested
        case photoCaptureRequested
        case retakeRequested
    }

    enum Delegate: Equatable {
        case permissionAccessFailed(PermissionKind)
        case handEvent(CameraHandEvent)
        case voiceRequested
        case photoRequested
        case videoRequested
    }

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
            switch action {
            case .cameraViewAppeared:
                return .send(.camera(.viewAppeared))

            case .cameraViewDisappeared:
                return .merge(
                    .send(.camera(.viewDisappeared)),
                    .send(.photo(.cancelGesture)),
                    .send(.video(.cancelRequested))
                )

            case .cameraActivationRequested:
                return .send(.camera(.activationRequested))

            case .prepareVideoRecordingRequested:
                guard state.camera.isViewVisible else { return .none }
                return .send(.video(.prepareRequested))

            case .cameraSwitchRequested:
                guard state.camera.previewConnector != nil,
                      !state.camera.isSwitching,
                      !state.photo.isCapturing,
                      state.photo.capturedData == nil,
                      state.video.phase == .idle else { return .none }
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

            case .photo(.delegate(.captureRequested)):
                return .send(.delegate(.photoRequested))

            case let .photoGestureEvent(event):
                guard state.camera.isViewVisible,
                      state.camera.previewConnector != nil,
                      !state.camera.isSwitching,
                      state.video.phase == .idle else {
                    if case .fistHeld = event {
                        return .send(.photo(.disarmGesture))
                    }
                    return .none
                }
                return .send(.photo(.gestureEvent(event)))

            case .cancelPhotoGesture:
                return .send(.photo(.cancelGesture))

            case .voiceButtonTapped:
                return .send(.delegate(.voiceRequested))

            case .photoButtonTapped:
                return .send(.delegate(.photoRequested))

            case .videoButtonTapped:
                return .send(.delegate(.videoRequested))

            case .videoRecordRequested:
                guard state.camera.isViewVisible,
                      state.camera.previewConnector != nil,
                      !state.camera.isSwitching,
                      !state.photo.isCapturing,
                      !state.photo.isScheduled,
                      state.photo.capturedData == nil,
                      state.video.phase == .idle else { return .none }
                return .merge(
                    .send(.photo(.disarmGesture)),
                    .send(.video(.recordRequested))
                )

            case .videoRetakeRequested:
                return .send(.video(.retakeRequested))

            case .photoCaptureRequested:
                guard state.camera.isViewVisible,
                      state.camera.previewConnector != nil,
                      !state.camera.isSwitching,
                      state.video.phase == .idle else { return .none }
                return .send(.photo(.captureRequested))

            case .retakeRequested:
                return .send(.photo(.retakeRequested))

            case .photo(.captured):
                if !state.camera.isViewVisible { state.photo.capturedData = nil }
                return .none

            case .camera, .photo, .video, .delegate:
                return .none
            }
        }
    }
}
