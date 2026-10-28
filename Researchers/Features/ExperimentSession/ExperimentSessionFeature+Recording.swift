import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

extension ExperimentSessionFeature {
    var recordingReducer: Reduce<State, Action> {
        Reduce { state, action in
            switch action {
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

            default:
                return .none
            }
        }
    }
}
