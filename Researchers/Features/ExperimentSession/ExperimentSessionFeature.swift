import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

@Reducer
struct ExperimentSessionFeature {
    enum VoicePhase: Equatable {
        case hidden
        case starting
        case recording
        case stopping
        case finished
    }

    enum VideoPhase: Equatable {
        case idle
        case starting
        case recording(Date)
        case preview(URL)
    }

    @ObservableState
    struct State: Equatable {
        var permissions = SessionPermissionsFeature.State()
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
        var voicePhase: VoicePhase = .hidden
        var voiceSessionID = UUID()
        var voiceTranscript = ""
        var voiceRecording: SpeechRecording?
        var voiceErrorMessage: String?
    }

    enum Action: Equatable {
        case cameraViewAppeared
        case cameraViewDisappeared
        case permissions(SessionPermissionsFeature.Action)
        case cameraStarted(UUID, CameraPreviewConnector)
        case cameraSwitchRequested
        case cameraSwitched(CameraPreviewConnector)
        case cameraStartFailed(UUID, String)
        case cameraSwitchFailed(String)
        case cameraErrorDismissed
        case handEvent(CameraHandEvent)
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
        case voiceButtonTapped
        case voiceOverlayAppeared
        case voiceStartRequested
        case voiceStarted(UUID)
        case voiceStartPermissionFailed(UUID)
        case voiceStartFailed(UUID, String)
        case voiceEvent(UUID, SpeechRecordingEvent)
        case voiceStopRequested
        case voiceStopped(UUID, SpeechRecording?)
        case voiceRetakeRequested
        case voiceCloseRequested
        case voiceErrorDismissed
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case timerTick
        case handTracking
        case photoCaptureDelay
        case videoRecording
        case voiceStream
        case voiceStop
    }

    private func cancelScheduledPhoto(in state: inout State) -> Effect<Action> {
        state.isPhotoCaptureScheduled = false
        return .cancel(id: CancelID.photoCaptureDelay)
    }

    @Dependency(\.cameraSessionClient) var cameraSessionClient
    @Dependency(\.speechRecordingClient) var speechRecordingClient

    var body: some Reducer<State, Action> {
        Scope(state: \.permissions, action: \.permissions) {
            SessionPermissionsFeature()
        }

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
                    .send(.permissions(.cancelRequest)),
                    .send(.voiceCloseRequested),
                    .cancel(id: CancelID.handTracking),
                    .cancel(id: CancelID.videoRecording),
                    cancelScheduledPhoto(in: &state),
                    .run { _ in
                        await cameraSessionClient.cancelVideoRecording()
                        if let videoURL { await cameraSessionClient.discardVideo(videoURL) }
                    },
                    .run { _ in await cameraSessionClient.deactivate(ownerID) }
                )

            case .permissions(.microphoneStatusUpdated(.authorized)):
                guard state.isCameraViewVisible else { return .none }
                return .run { _ in
                    try? await cameraSessionClient.prepareVideoRecording()
                }

            case .permissions(.camera(.statusUpdated(.authorized))):
                guard state.isCameraViewVisible else { return .none }
                let ownerID = state.cameraOwnerID
                return .run { send in
                    do {
                        try await cameraSessionClient.activate(ownerID)
                        let connector = await cameraSessionClient.previewConnector()
                        await send(.cameraStarted(ownerID, connector))
                    } catch let error as PermissionAccessError {
                        await send(.permissions(.accessFailed(error.kind)))
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

            case let .handEvent(.openHandHeld(detectedAt)):
                guard state.isCameraViewVisible, state.previewConnector != nil,
                      !state.isPhotoCaptureScheduled, !state.isCapturingPhoto,
                      !state.isCameraSwitching, state.capturedPhotoData == nil,
                      state.voicePhase == .hidden, state.videoPhase == .idle,
                      detectedAt.timeIntervalSinceNow > -0.5 else { return .none }
                state.isPhotoGestureArmed = true
                return .none

            case let .handEvent(.fistHeld(detectedAt)):
                let wasArmed = state.isPhotoGestureArmed
                state.isPhotoGestureArmed = false
                guard state.isCameraViewVisible, state.previewConnector != nil,
                      !state.isPhotoCaptureScheduled, !state.isCapturingPhoto,
                      !state.isCameraSwitching, state.capturedPhotoData == nil,
                      state.voicePhase == .hidden, state.videoPhase == .idle,
                      wasArmed,
                      detectedAt.timeIntervalSinceNow > -0.5 else { return .none }
                state.isPhotoCaptureScheduled = true
                return .run { send in
                    try await Task.sleep(for: .seconds(5))
                    await send(.photoCaptureDelayElapsed)
                }
                .cancellable(id: CancelID.photoCaptureDelay, cancelInFlight: true)

            case let .handEvent(.oneFingerHeld(detectedAt)):
                guard state.isCameraViewVisible, state.previewConnector != nil,
                      !state.isCameraSwitching, !state.isPhotoCaptureScheduled,
                      !state.isCapturingPhoto, state.capturedPhotoData == nil,
                      state.videoPhase == .idle,
                      detectedAt.timeIntervalSinceNow > -0.5 else { return .none }
                state.isPhotoGestureArmed = false
                switch state.voicePhase {
                case .hidden: return .send(.voiceButtonTapped)
                case .recording: return .send(.voiceStopRequested)
                case .starting, .stopping, .finished: return .none
                }

            case let .handEvent(.threeFingersHeld(detectedAt)):
                guard !state.isPhotoCaptureScheduled, !state.isCapturingPhoto,
                      detectedAt.timeIntervalSinceNow > -0.5 else { return .none }
                return .send(.videoRecordRequested)

            case .videoRecordRequested:
                guard state.isCameraViewVisible, state.previewConnector != nil,
                      !state.isCameraSwitching, !state.isCapturingPhoto,
                      !state.isPhotoCaptureScheduled, state.capturedPhotoData == nil,
                      state.voicePhase == .hidden, state.videoPhase == .idle else { return .none }
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
                        await send(.permissions(.accessFailed(error.kind)))
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
                return .send(.photoCaptureRequested)

            case .photoCaptureRequested:
                guard state.isCameraViewVisible, state.previewConnector != nil,
                      !state.isCapturingPhoto,
                      state.capturedPhotoData == nil, !state.isCameraSwitching,
                      state.voicePhase == .hidden,
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

            case .voiceButtonTapped:
                guard state.voicePhase == .hidden, state.isCameraViewVisible,
                      !state.isCapturingPhoto, state.capturedPhotoData == nil,
                        state.videoPhase == .idle else { return .none }
                state.isPhotoGestureArmed = false
                state.voiceTranscript = ""
                state.voiceRecording = nil
                state.voiceErrorMessage = nil
                state.voiceSessionID = UUID()
                state.voicePhase = .starting
                return cancelScheduledPhoto(in: &state)

            case .voiceOverlayAppeared:
                guard state.voicePhase == .starting else { return .none }
                return .send(.voiceStartRequested)

            case .voiceStartRequested:
                guard state.voicePhase == .starting else { return .none }
                let id = state.voiceSessionID
                return .run { send in
                    do {
                        let events = try await speechRecordingClient.start()
                        await send(.voiceStarted(id))
                        for await event in events {
                            await send(.voiceEvent(id, event))
                        }
                    } catch is CancellationError {
                        return
                    } catch let error as PermissionAccessError {
                        await send(.permissions(.accessFailed(error.kind)))
                        await send(.voiceStartPermissionFailed(id))
                    } catch {
                        await send(.voiceStartFailed(id, error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.voiceStream, cancelInFlight: true)

            case let .voiceStarted(id):
                guard id == state.voiceSessionID,
                        state.voicePhase == .starting else { return .none }
                state.voicePhase = .recording
                return .none

            case let .voiceStartPermissionFailed(id):
                guard id == state.voiceSessionID,
                        state.voicePhase == .starting else { return .none }
                state.voicePhase = .hidden
                return .none

            case let .voiceStartFailed(id, message):
                guard id == state.voiceSessionID,
                        state.voicePhase == .starting else { return .none }
                state.voicePhase = .hidden
                state.voiceErrorMessage = message
                return .none

            case let .voiceEvent(id, event):
                guard id == state.voiceSessionID else { return .none }
                switch event {
                case let .transcript(text):
                    if state.voicePhase == .recording || state.voicePhase == .stopping {
                        state.voiceTranscript = text
                    }
                case let .finished(recording):
                    state.voiceTranscript = recording.transcript
                    state.voiceRecording = recording
                    state.voicePhase = .finished
                case let .failed(message):
                    state.voicePhase = .hidden
                    state.voiceErrorMessage = message
                }
                return .none

            case .voiceStopRequested:
                guard state.voicePhase == .recording else { return .none }
                state.voicePhase = .stopping
                let id = state.voiceSessionID
                return .run { send in
                    let recording = await speechRecordingClient.stop()
                    await send(.voiceStopped(id, recording))
                }
                .cancellable(id: CancelID.voiceStop, cancelInFlight: true)

            case let .voiceStopped(id, recording):
                guard id == state.voiceSessionID,
                        state.voicePhase == .stopping else { return .none }
                if let recording {
                    state.voiceRecording = recording
                    state.voiceTranscript = recording.transcript
                    state.voicePhase = .finished
                } else {
                    state.voicePhase = .hidden
                    state.voiceErrorMessage = "음성 기록을 완료하지 못했습니다. 다시 시도해 주세요."
                }
                return .cancel(id: CancelID.voiceStream)

            case .voiceRetakeRequested:
                guard state.voicePhase == .finished else { return .none }
                state.voiceRecording = nil
                state.voiceTranscript = ""
                state.voiceErrorMessage = nil
                state.voiceSessionID = UUID()
                state.voicePhase = .starting
                return .send(.voiceStartRequested)

            case .voiceCloseRequested:
                guard state.voicePhase != .hidden else { return .none }
                state.voicePhase = .hidden
                state.voiceSessionID = UUID()
                state.voiceTranscript = ""
                state.voiceRecording = nil
                return .merge(
                    .cancel(id: CancelID.voiceStream),
                    .cancel(id: CancelID.voiceStop),
                    .run { _ in await speechRecordingClient.cancel() }
                )

            case .voiceErrorDismissed:
                state.voiceErrorMessage = nil
                return .none

            case .permissions:
                return .none
            }
        }
    }
}
