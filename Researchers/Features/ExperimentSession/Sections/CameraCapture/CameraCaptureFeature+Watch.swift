import AVFoundation
import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

extension CameraCaptureFeature {
    func reduceWatch(state: inout State, action: Action) -> Effect<Action>? {
        if let effect = watchPhotoEvent(state: &state, action: action) { return effect }
        if let effect = watchVideoDiscardEvent(state: &state, action: action) { return effect }
        if let effect = watchVideoEvent(state: &state, action: action) { return effect }
        switch action {
        case let .watchCommand(command):
            do {
                let input = try WatchMediaCommandHandler.input(
                    for: command, activeExperimentID: state.photo.experimentID
                )
                return try executeWatch(input, command: command, state: &state)
            } catch {
                return watchReply(command, phase: .failed, error: error as? WatchExperimentError)
            }
        default:
            return nil
        }
    }

    private func watchPhotoEvent(state: inout State, action: Action) -> Effect<Action>? {
        guard let command = state.watchPhotoRequest else { return nil }
        switch action {
        case let .photo(.delegate(.captureScheduled(id, date))):
            guard recordID(command) == id, state.photo.isScheduled else { return nil }
            return watchReply(
                command, phase: .processing, kind: .photo, recordPhase: .capturing, date: date
            )
        case .photo(.captured):
            return watchReply(
                command, phase: .processing, kind: .photo, recordPhase: .review, canAutoSave: true
            )
        case .photo(.saved):
            state.watchPhotoRequest = nil
            return finishWatchReview(command, kind: .photo, state: &state)
        case .photo(.saveFailed):
            return failWatchReview(command, kind: .photo, state: &state)
        case .photo(.captureFailed):
            state.watchPhotoRequest = nil
            return watchReply(
                command, phase: .failed, error: .cameraUnavailable,
                kind: .photo, recordPhase: .failed, originalRetained: false
            )
        case .photo(.cancelGesture):
            guard !state.photo.isCapturing, state.photo.capturedData == nil else { return nil }
            state.watchPhotoRequest = nil
            return watchReply(
                command, phase: .completed, kind: .photo, recordPhase: .cancelled
            )
        default: return nil
        }
    }

    private func watchVideoEvent(state: inout State, action: Action) -> Effect<Action>? {
        guard let command = state.watchVideoRequest else { return nil }
        switch action {
        case let .video(.started(_, date)):
            return watchReply(
                command, phase: .processing, kind: .video, recordPhase: .recording, date: date
            )
        case .video(.recorded):
            let preview = watchReply(
                command, phase: .processing, kind: .video, recordPhase: .previewing
            )
            return .merge(preview, finishWatchStop(state: &state))
        case .video(.playbackFinished):
            return watchReply(
                command, phase: .processing, kind: .video, recordPhase: .review, canAutoSave: true
            )
        case .video(.saved):
            state.watchVideoRequest = nil
            return finishWatchReview(command, kind: .video, state: &state)
        case .video(.saveFailed):
            return failWatchReview(command, kind: .video, state: &state)
        case .video(.recordingFailed):
            state.watchVideoRequest = nil
            return .merge(
                watchReply(
                    command, phase: .failed, error: .cameraUnavailable,
                    kind: .video, recordPhase: .failed, originalRetained: false
                ),
                finishWatchStop(state: &state, error: .cameraUnavailable)
            )
        case let .video(.delegate(.permissionAccessFailed(kind))):
            state.watchVideoRequest = nil
            return .merge(
                watchReply(
                    command, phase: .failed, error: .permissionDenied,
                    kind: .video, recordPhase: .failed, originalRetained: false
                ),
                finishWatchStop(state: &state, error: .permissionDenied),
                .send(.delegate(.permissionAccessFailed(kind)))
            )
        default: return nil
        }
    }

    private func watchVideoDiscardEvent(state: inout State, action: Action) -> Effect<Action>? {
        guard case let .video(.watchPauseDiscarded(id)) = action,
              let command = state.watchVideoRequest,
              id == state.video.sessionID, state.video.phase == .idle else { return nil }
        state.watchVideoRequest = nil
        return .merge(
            watchReply(command, phase: .completed, kind: .video, recordPhase: .cancelled),
            finishWatchStop(state: &state, error: .invalidState)
        )
    }

    private func finishWatchStop(
        state: inout State, error: WatchExperimentError? = nil
    ) -> Effect<Action> {
        guard let stop = state.watchStopRequest else { return .none }
        state.watchStopRequest = nil
        return watchReply(
            stop, phase: error == nil ? .completed : .failed, error: error,
            kind: .video, recordPhase: error == nil ? .previewing : .failed
        )
    }

    private func executeWatch(
        _ input: WatchMediaCommandHandler.Input, command: WatchExperimentCommand,
        state: inout State
    ) throws -> Effect<Action> {
        switch input {
        case let .takePhoto(id):
            try requireCamera(state)
            guard state.video.phase == .idle, !state.photo.isCapturing,
                  !state.photo.isScheduled, state.photo.capturedData == nil else {
                throw WatchExperimentError.phoneBusy
            }
            state.watchPhotoRequest = command
            state.photo.pendingWatchCaptureID = id
            return .send(.photo(.watchCaptureRequested(id)))
        case let .startVideo(id):
            try requireCamera(state)
            guard state.video.phase == .idle, !state.photo.isCapturing,
                  !state.photo.isScheduled, state.photo.capturedData == nil else {
                throw WatchExperimentError.phoneBusy
            }
            state.watchVideoRequest = command
            return .send(.video(.watchRecordRequested(id)))
        case let .stopVideo(id):
            guard state.watchVideoRequest.map(recordID) == id,
                  state.video.phase != .idle else { throw WatchExperimentError.invalidState }
            if case .preview = state.video.phase {
                throw WatchExperimentError.invalidState
            }
            state.watchStopRequest = command
            return .send(.video(.stopRequested))
        case let .confirm(id):
            return try confirmWatch(id, command: command, state: &state)
        case let .cancel(id):
            return try cancelWatch(id, command: command, state: &state)
        }
    }

    private func confirmWatch(
        _ id: UUID, command: WatchExperimentCommand, state: inout State
    ) throws -> Effect<Action> {
            guard !state.photo.isSaving, !state.video.isSaving else {
                throw WatchExperimentError.phoneBusy
            }
            state.watchReviewRequest = command
            if state.photo.recordID == id { return .send(.photo(.saveRequested)) }
            if state.video.recordID == id { return .send(.video(.saveRequested)) }
            state.watchReviewRequest = nil
            throw WatchExperimentError.invalidState
    }

    private func cancelWatch(
        _ id: UUID, command: WatchExperimentCommand, state: inout State
    ) throws -> Effect<Action> {
        guard !state.photo.isSaving, !state.video.isSaving, !state.photo.isCapturing else {
            throw WatchExperimentError.phoneBusy
        }
        let cancel: Effect<Action>
        let kind: WatchRecordSnapshot.Kind
        var interruptedCapture: Effect<Action> = .none
        if state.watchPhotoRequest.map(recordID) == id {
            kind = .photo
            state.photo.pendingWatchCaptureID = nil
            if state.photo.capturedData == nil, let original = state.watchPhotoRequest {
                interruptedCapture = watchReply(original, phase: .failed, error: .requestExpired)
            }
            state.watchPhotoRequest = nil
            cancel = .send(.photo(.retakeRequested))
        } else if state.video.recordID == id, case .preview = state.video.phase {
            kind = .video
            state.watchVideoRequest = nil
            cancel = .send(.video(.retakeRequested))
        } else {
            throw WatchExperimentError.invalidState
        }
        return .concatenate(cancel, interruptedCapture, watchReply(
            command, phase: .completed, kind: kind, recordPhase: .cancelled
        ))
    }

    private func requireCamera(_ state: State) throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw WatchExperimentError.permissionDenied
        }
        guard state.camera.isViewVisible, state.camera.previewConnector != nil,
              !state.camera.isSwitching else { throw WatchExperimentError.cameraUnavailable }
    }

    private func failWatchReview(
        _ command: WatchExperimentCommand, kind: WatchRecordSnapshot.Kind, state: inout State
    ) -> Effect<Action> {
        let failed = watchReply(
            command, phase: .failed, error: .storageFailed, kind: kind,
            recordPhase: .failed, originalRetained: true
        )
        guard let review = state.watchReviewRequest else { return failed }
        state.watchReviewRequest = nil
        return .merge(failed, watchReply(
            review, phase: .failed, error: .storageFailed, kind: kind,
            recordPhase: .failed, originalRetained: true
        ))
    }

    private func finishWatchReview(
        _ command: WatchExperimentCommand, kind: WatchRecordSnapshot.Kind, state: inout State
    ) -> Effect<Action> {
        let saved = watchReply(command, phase: .completed, kind: kind, recordPhase: .saved)
        guard let review = state.watchReviewRequest else { return saved }
        state.watchReviewRequest = nil
        return .merge(saved, watchReply(
            review, phase: .completed, kind: kind, recordPhase: .saved
        ))
    }

    private func watchReply(
        _ command: WatchExperimentCommand, phase: WatchExperimentResponse.Phase,
        error: WatchExperimentError? = nil, kind: WatchRecordSnapshot.Kind? = nil,
        recordPhase: WatchRecordSnapshot.Phase = .failed, date: Date? = nil,
        canAutoSave: Bool = false, originalRetained: Bool? = nil
    ) -> Effect<Action> {
        .send(.delegate(.watchResponse(WatchExperimentResponse(
            requestID: command.requestID, phase: phase, error: error,
            record: kind.map {
                WatchRecordSnapshot(
                    id: recordID(command), kind: $0, phase: recordPhase,
                    startedAt: date, canAutoSave: canAutoSave,
                    originalRetained: originalRetained
                        ?? [.review, .previewing, .saved].contains(recordPhase), error: error
                )
            }
        ))))
    }

    private func recordID(_ command: WatchExperimentCommand) -> UUID {
        command.targetID ?? command.requestID
    }
}
