import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

@Reducer
struct CameraCaptureFeature {
    enum VideoPhase: Equatable {
        case idle
        case starting
        case recording(Date)
        case preview(URL)
    }

    @ObservableState
    struct State: Equatable {
        var cameraOwnerID = UUID()
        var isCameraViewVisible = false
        var cameraErrorMessage: String?
        var previewConnector: CameraPreviewConnector?
        var isCameraSwitching = false
        var isPhotoCaptureScheduled = false
        var isCapturingPhoto = false
        var capturedPhotoData: Data?
        var isPhotoGestureArmed = false
        var videoPhase: VideoPhase = .idle
        var videoSessionID = UUID()
    }

    enum Action: Equatable {
        case cameraViewAppeared
        case cameraViewDisappeared
        case cameraActivationRequested
        case prepareVideoRecordingRequested
        case delegate(Delegate)
        case cameraStarted(UUID, CameraPreviewConnector)
        case cameraSwitchRequested
        case cameraSwitched(CameraPreviewConnector)
        case cameraStartFailed(UUID, String)
        case cameraSwitchFailed(String)
        case cameraErrorDismissed
        case handEvent(CameraHandEvent)
        case photoGestureEvent(CameraHandEvent)
        case cancelPhotoGesture
        case voiceButtonTapped
        case photoButtonTapped
        case videoButtonTapped
        case videoRecordRequested
        case videoStarted(UUID, Date)
        case videoRecorded(UUID, URL)
        case videoRecordingFailed(UUID, String)
        case videoRetakeRequested
        case photoCaptureDelayElapsed
        case photoCaptureRequested
        case photoCaptured(Data)
        case photoCaptureFailed(String)
        case retakeRequested
    }

    enum Delegate: Equatable {
        case permissionAccessFailed(PermissionKind)
        case handEvent(CameraHandEvent)
        case voiceRequested
        case photoRequested
        case videoRequested
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case handTracking
        case photoCaptureDelay
        case videoRecording
    }

    private func cancelScheduledPhoto(in state: inout State) -> Effect<Action> {
        state.isPhotoCaptureScheduled = false
        return .cancel(id: CancelID.photoCaptureDelay)
    }

    @Dependency(\.cameraSessionClient) var cameraSessionClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .cameraViewAppeared:
                guard !state.isCameraViewVisible else { return .none }
                state.isCameraViewVisible = true
                state.cameraOwnerID = UUID()
                return .none

            case .cameraViewDisappeared:
                guard state.isCameraViewVisible else { return .none }
                state.isCameraViewVisible = false
                state.isPhotoGestureArmed = false
                let videoURL: URL?
                if case let .preview(url) = state.videoPhase {
                    videoURL = url
                } else {
                    videoURL = nil
                }
                state.videoPhase = .idle
                state.videoSessionID = UUID()
                let ownerID = state.cameraOwnerID
                return .merge(
                    .cancel(id: CancelID.handTracking),
                    .cancel(id: CancelID.videoRecording),
                    cancelScheduledPhoto(in: &state),
                    .run { _ in
                        await cameraSessionClient.cancelVideoRecording()
                        if let videoURL { await cameraSessionClient.discardVideo(videoURL) }
                    },
                    .run { _ in await cameraSessionClient.deactivate(ownerID) }
                )

            case .prepareVideoRecordingRequested:
                guard state.isCameraViewVisible else { return .none }
                return .run { _ in
                    try? await cameraSessionClient.prepareVideoRecording()
                }

            case .cameraActivationRequested:
                guard state.isCameraViewVisible else { return .none }
                let ownerID = state.cameraOwnerID
                return .run { send in
                    do {
                        try await cameraSessionClient.activate(ownerID)
                        let connector = await cameraSessionClient.previewConnector()
                        await send(.cameraStarted(ownerID, connector))
                    } catch let error as PermissionAccessError {
                        await send(.delegate(.permissionAccessFailed(error.kind)))
                    } catch {
                        await send(.cameraStartFailed(ownerID, error.localizedDescription))
                    }
                }

            case let .cameraStarted(ownerID, connector):
                guard state.isCameraViewVisible, ownerID == state.cameraOwnerID else {
                    return .run { _ in await cameraSessionClient.deactivate(ownerID) }
                }
                state.cameraErrorMessage = nil
                state.previewConnector = connector
                return .run { send in
                    for await event in await cameraSessionClient.handEvents() {
                        await send(.handEvent(event))
                    }
                }
                .cancellable(id: CancelID.handTracking, cancelInFlight: true)

            case .cameraSwitchRequested:
                guard state.previewConnector != nil, !state.isCameraSwitching,
                      !state.isCapturingPhoto, state.capturedPhotoData == nil,
                      state.videoPhase == .idle else { return .none }
                state.isCameraSwitching = true
                state.isPhotoGestureArmed = false
                return .merge(
                    cancelScheduledPhoto(in: &state),
                    .run { send in
                        do {
                            try await cameraSessionClient.switchCamera()
                            let connector = await cameraSessionClient.previewConnector()
                            await send(.cameraSwitched(connector))
                        } catch {
                            await send(.cameraSwitchFailed(error.localizedDescription))
                        }
                    }
                )

            case let .cameraSwitched(connector):
                state.isCameraSwitching = false
                state.cameraErrorMessage = nil
                state.previewConnector = connector
                return .none

            case let .cameraStartFailed(ownerID, message):
                guard state.isCameraViewVisible,
                        ownerID == state.cameraOwnerID else { return .none }
                state.cameraErrorMessage = message
                return .none

            case let .cameraSwitchFailed(message):
                state.isCameraSwitching = false
                state.cameraErrorMessage = message
                return .none

            case .cameraErrorDismissed:
                state.cameraErrorMessage = nil
                return .none

            case let .handEvent(event):
                if case .oneFingerHeld = event { state.isPhotoGestureArmed = false }
                return .send(.delegate(.handEvent(event)))

            case let .photoGestureEvent(.openHandHeld(detectedAt)):
                guard state.isCameraViewVisible, state.previewConnector != nil,
                      !state.isPhotoCaptureScheduled, !state.isCapturingPhoto,
                      !state.isCameraSwitching, state.capturedPhotoData == nil,
                      state.videoPhase == .idle,
                      detectedAt.timeIntervalSinceNow > -0.5 else { return .none }
                state.isPhotoGestureArmed = true
                return .none

            case let .photoGestureEvent(.fistHeld(detectedAt)):
                let wasArmed = state.isPhotoGestureArmed
                state.isPhotoGestureArmed = false
                guard state.isCameraViewVisible, state.previewConnector != nil,
                      !state.isPhotoCaptureScheduled, !state.isCapturingPhoto,
                      !state.isCameraSwitching, state.capturedPhotoData == nil,
                      state.videoPhase == .idle,
                      wasArmed,
                      detectedAt.timeIntervalSinceNow > -0.5 else { return .none }
                state.isPhotoCaptureScheduled = true
                return .run { send in
                    try await Task.sleep(for: .seconds(5))
                    await send(.photoCaptureDelayElapsed)
                }
                .cancellable(id: CancelID.photoCaptureDelay, cancelInFlight: true)

            case .photoGestureEvent:
                return .none

            case .cancelPhotoGesture:
                state.isPhotoGestureArmed = false
                return cancelScheduledPhoto(in: &state)

            case .voiceButtonTapped:
                return .send(.delegate(.voiceRequested))

            case .photoButtonTapped:
                return .send(.delegate(.photoRequested))

            case .videoButtonTapped:
                return .send(.delegate(.videoRequested))

            case .videoRecordRequested:
                guard state.isCameraViewVisible, state.previewConnector != nil,
                      !state.isCameraSwitching, !state.isCapturingPhoto,
                      !state.isPhotoCaptureScheduled, state.capturedPhotoData == nil,
                      state.videoPhase == .idle else { return .none }
                state.isPhotoGestureArmed = false
                state.videoSessionID = UUID()
                state.videoPhase = .starting
                let id = state.videoSessionID
                return .run { send in
                    do {
                        let url = try await cameraSessionClient.recordVideo {
                            Task { await send(.videoStarted(id, .now)) }
                        }
                        guard !Task.isCancelled else {
                            await cameraSessionClient.discardVideo(url)
                            return
                        }
                        await send(.videoRecorded(id, url))
                    } catch let error as PermissionAccessError {
                        await send(.delegate(.permissionAccessFailed(error.kind)))
                        await send(.videoRecordingFailed(id, error.localizedDescription))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.videoRecordingFailed(id, error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.videoRecording, cancelInFlight: true)

            case let .videoStarted(id, startedAt):
                guard id == state.videoSessionID,
                        state.videoPhase == .starting else { return .none }
                state.videoPhase = .recording(startedAt)
                return .none

            case let .videoRecorded(id, url):
                guard id == state.videoSessionID, state.isCameraViewVisible else {
                    return .run { _ in await cameraSessionClient.discardVideo(url) }
                }
                state.videoPhase = .preview(url)
                return .none

            case let .videoRecordingFailed(id, message):
                guard id == state.videoSessionID,
                        state.isCameraViewVisible else { return .none }
                state.videoPhase = .idle
                state.cameraErrorMessage = message
                return .none

            case .videoRetakeRequested:
                guard case let .preview(url) = state.videoPhase else { return .none }
                state.videoPhase = .idle
                return .run { _ in await cameraSessionClient.discardVideo(url) }

            case .photoCaptureDelayElapsed:
                guard state.isPhotoCaptureScheduled else { return .none }
                return .send(.delegate(.photoRequested))

            case .photoCaptureRequested:
                guard state.isCameraViewVisible, state.previewConnector != nil,
                      !state.isCapturingPhoto,
                      state.capturedPhotoData == nil, !state.isCameraSwitching,
                      state.videoPhase == .idle else { return .none }
                let cancelDelay = cancelScheduledPhoto(in: &state)
                state.isCapturingPhoto = true
                return .merge(
                    cancelDelay,
                    .run { send in
                        do {
                            await send(
                                .photoCaptured(
                                    try await cameraSessionClient.capturePhoto()
                                )
                            )
                        } catch {
                            await send(.photoCaptureFailed(error.localizedDescription))
                        }
                    }
                )

            case let .photoCaptured(data):
                state.isCapturingPhoto = false
                if state.isCameraViewVisible { state.capturedPhotoData = data }
                return .none

            case let .photoCaptureFailed(message):
                state.isCapturingPhoto = false
                state.cameraErrorMessage = message
                return .none

            case .retakeRequested:
                state.capturedPhotoData = nil
                return cancelScheduledPhoto(in: &state)

            case .delegate:
                return .none
            }
        }
    }
}
