import AVFoundation
import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared
import OSLog

private let watchPhotoLog = Logger(subsystem: "Labcord", category: "Capture")

extension CameraCaptureFeature {
    func reduceWatch(state: inout State, action: Action) -> Effect<Action>? {
        if let effect = watchPhotoRetake(state: &state, action: action) { return effect }
        if let effect = watchPhotoEvent(state: &state, action: action) { return effect }
        if let effect = watchVideoEvent(state: &state, action: action) { return effect }
        if let effect = watchFollowUp(state: &state, action: action) { return effect }
        switch action {
        case let .watchCommand(command):
            guard PhoneWatchExperimentCoordinator.shared.isAwaitingCameraCommand(
                command.requestID
            ) else { return .none }
            do {
                let input = try WatchMediaCommandHandler.input(
                    for: command, activeExperimentID: state.photo.experimentID
                )
                return try executeWatch(input, command: command, state: &state)
            } catch {
                return watchReply(
                    command, phase: .failed, error: error as? WatchExperimentError ?? .invalidState
                )
            }
        case let .watchCommandExpired(requestID):
            expireWatchCommand(requestID, state: &state)
            return .none
        default:
            return nil
        }
    }

    private func expireWatchCommand(_ requestID: UUID, state: inout State) {
        if state.watchPhotoRequest?.requestID == requestID,
           let id = state.photo.pendingWatchCaptureID,
           state.watchPhotoRequest.map(recordID) == id {
            state.watchPhotoRequest = nil
            state.photo.pendingWatchCaptureID = nil
        }
        if state.watchStopRequest?.requestID == requestID { state.watchStopRequest = nil }
        if state.watchReviewRequest?.requestID == requestID { state.watchReviewRequest = nil }
    }

    private func watchPhotoRetake(state: inout State, action: Action) -> Effect<Action>? {
        let cancellation: WatchExperimentCommand?
        switch action {
        case .photo(.retakeRequested):
            cancellation = nil
        case let .photo(.watchCancelRequested(id)):
            guard let request = state.watchPhotoCancellationRequest, recordID(request) == id
            else { return nil }
            state.watchPhotoCancellationRequest = nil
            if state.photo.requestedRecordID == id || state.photo.recordID == id {
                return watchReply(request, phase: .failed, error: .phoneBusy)
            }
            cancellation = request
        default:
            return nil
        }
        guard let command = state.watchPhotoRequest,
              cancellation.map(recordID) == nil || cancellation.map(recordID) == recordID(command),
              state.photo.requestedRecordID != recordID(command),
              state.photo.recordID != recordID(command) else {
            return cancellation.map { watchReply($0, phase: .failed, error: .invalidState) }
        }
        state.watchPhotoRequest = nil
        let source = cancellation == nil ? "phonePreview" : "watchCancel"
        let id = recordID(command)
        watchPhotoLog.notice("""
            photo cancelled id=\(id, privacy: .public) source=\(source, privacy: .public)
            """)
        let cancelled = watchReply(
            command, phase: .completed, kind: .photo, recordPhase: .cancelled
        )
        guard let cancellation else { return cancelled }
        return .merge(
            cancelled,
            watchReply(cancellation, phase: .completed, kind: .photo, recordPhase: .cancelled)
        )
    }

    private func watchFollowUp(state: inout State, action: Action) -> Effect<Action>? {
        switch action {
        case let .video(.watchRecordRequested(id)):
            guard let start = state.watchVideoRequest, recordID(start) == id,
                  state.video.requestedRecordID != id || state.video.phase != .starting else {
                return nil
            }
            state.watchVideoRequest = nil
            return watchReply(start, phase: .failed, error: .phoneBusy)
        case let .photo(.watchSaveRequested(id)), let .video(.watchSaveRequested(id)):
            guard let review = state.watchReviewRequest, recordID(review) == id else { return nil }
            if state.photo.recordID == id && state.photo.isSaving
                || state.video.recordID == id && state.video.isSaving { return nil }
            state.watchReviewRequest = nil
            return watchReply(review, phase: .failed, error: .invalidState)
        case let .video(.watchStopRequested(id)):
            guard let stop = state.watchStopRequest, recordID(stop) == id,
                  state.video.requestedRecordID != id || state.video.phase == .idle else {
                return nil
            }
            state.watchStopRequest = nil
            return watchReply(stop, phase: .failed, error: .invalidState)
        case let .video(.watchCancelRequested(id)):
            guard let request = state.watchVideoCancellationRequest, recordID(request) == id,
                  state.video.recordID == id else { return nil }
            state.watchVideoCancellationRequest = nil
            return watchReply(request, phase: .failed, error: .phoneBusy)
        default:
            return nil
        }
    }

    private func watchPhotoEvent(state: inout State, action: Action) -> Effect<Action>? {
        guard let command = state.watchPhotoRequest,
              matchesPhotoEvent(action, id: recordID(command), photo: state.photo)
        else { return nil }
        switch action {
        case let .photo(.watchCaptureRequested(id)):
            if state.photo.requestedRecordID == id, !state.photo.isScheduled { return nil }
            guard state.photo.requestedRecordID == id,
                  state.photo.isScheduled, let date = state.photo.scheduledAt else {
                state.watchPhotoRequest = nil
                state.photo.pendingWatchCaptureID = nil
                return watchReply(command, phase: .failed, error: .phoneBusy)
            }
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
        case let .photo(.captureFailed(_, _, error)):
            let id = recordID(command)
            watchPhotoLog.notice("photo failed id=\(id, privacy: .public) originalRetained=false")
            state.watchPhotoRequest = nil
            return watchReply(
                command, phase: .failed, error: error,
                kind: .photo, recordPhase: .failed, originalRetained: false
            )
        default: return nil
        }
    }

    private func watchVideoEvent(state: inout State, action: Action) -> Effect<Action>? {
        guard let command = state.watchVideoRequest,
              matchesVideoEvent(
                action, command: command, sessionID: state.video.sessionID
              ) else { return nil }
        switch action {
        case let .video(.started(_, date)):
            guard case .recording = state.video.phase else { return nil }
            return watchReply(
                command, phase: .processing, kind: .video, recordPhase: .recording, date: date
            )
        case .video(.recorded):
            let preview = watchReply(
                command, phase: .processing, kind: .video, recordPhase: .review,
                canAutoSave: true
            )
            return .merge(preview, finishWatchStop(state: &state))
        case .video(.saved):
            state.watchVideoRequest = nil
            return finishWatchReview(command, kind: .video, state: &state)
        case .video(.saveFailed):
            return failWatchReview(command, kind: .video, state: &state)
        case let .video(.recordingFailed(_, failure)):
            state.watchVideoRequest = nil
            return .merge(
                watchReply(
                    command, phase: .failed, error: failure.watchError,
                    kind: .video, recordPhase: .failed, originalRetained: false
                ),
                finishWatchStop(state: &state, error: failure.watchError)
            )
        case let .video(.cancelCleanupFinished(_, confirmed)):
            return finishVideoCancellation(command, state: &state, confirmed: confirmed)
        default: return nil
        }
    }

    private func finishVideoCancellation(
        _ command: WatchExperimentCommand, state: inout State, confirmed: Bool
    ) -> Effect<Action> {
        let affected = [command, state.watchVideoCancellationRequest,
                        state.watchReviewRequest, state.watchStopRequest].compactMap { $0 }
        state.watchVideoRequest = nil
        state.watchVideoCancellationRequest = nil
        state.watchReviewRequest = nil
        state.watchStopRequest = nil
        return .merge(affected.map { request in
            guard confirmed else { return watchUnknownVideo(request) }
            let rejected = request.operation == .confirmRecord || request.operation == .stopVideo
            return watchReply(
                request, phase: rejected ? .failed : .completed,
                error: rejected ? .invalidState : nil, kind: .video, recordPhase: .cancelled
            )
        })
    }

    private func watchUnknownVideo(_ command: WatchExperimentCommand) -> Effect<Action> {
        .send(.delegate(.watchResponse(.init(
            requestID: command.requestID, phase: .failed, error: .resultUnknown,
            record: .init(
                id: recordID(command), kind: .video, phase: .failed,
                originalRetained: nil, error: .resultUnknown
            )
        ))))
    }

    private func matchesPhotoEvent(_ action: Action, id: UUID, photo: PhotoFeature.State) -> Bool {
        switch action {
        case let .photo(.watchCaptureRequested(eventID)): eventID == id
        case let .photo(.captured(eventID, _)):
            eventID == id && photo.recordID == id && !photo.isSaving
        case let .photo(.saved(eventID)): eventID == id && photo.lastSavedRecordID == id
        case let .photo(.saveFailed(eventID, _)):
            eventID == id && photo.recordID == id && photo.saveError != nil
        case let .photo(.captureFailed(eventID, _, _)):
            eventID == id && photo.watchCaptureID == nil && photo.capturedData == nil
        default: false
        }
    }

    private func matchesVideoEvent(
        _ action: Action, command: WatchExperimentCommand, sessionID: UUID
    ) -> Bool {
        switch action {
        case let .video(.started(id, _)), let .video(.recorded(id, _)),
             let .video(.recordingFailed(id, _)):
            return sessionID == id
        case let .video(.saved(id)),
             let .video(.saveFailed(id, _)), let .video(.cancelCleanupFinished(id, _)):
            return recordID(command) == id
        default: return true
        }
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
            guard state.video.phase == .idle, state.watchVideoRequest == nil,
                  state.watchPhotoRequest == nil, !state.photo.isCapturing,
                  !state.photo.isScheduled, state.photo.capturedData == nil,
                  !state.photo.isSessionClosing, !state.video.isSessionClosing else {
                throw WatchExperimentError.phoneBusy
            }
            state.watchPhotoRequest = command
            state.photo.pendingWatchCaptureID = id
            return .send(.photo(.watchCaptureRequested(id)))
        case let .startVideo(id):
            try requireCamera(state)
            guard state.video.phase == .idle, state.watchVideoRequest == nil,
                  state.watchPhotoRequest == nil, !state.photo.isCapturing,
                  !state.photo.isScheduled, state.photo.capturedData == nil,
                  !state.photo.isSessionClosing, !state.video.isSessionClosing else {
                throw WatchExperimentError.phoneBusy
            }
            state.watchVideoRequest = command
            return .send(.video(.watchRecordRequested(id)))
        case let .stopVideo(id):
            guard state.watchVideoRequest.map(recordID) == id,
                  state.watchStopRequest == nil else { throw WatchExperimentError.invalidState }
            switch state.video.phase {
            case .starting, .recording: break
            case .idle, .preview:
                throw WatchExperimentError.invalidState
            }
            state.watchStopRequest = command
            return .send(.video(.watchStopRequested(id)))
        case let .confirm(id):
            return try confirmWatch(id, command: command, state: &state)
        case let .cancel(id):
            return try cancelWatch(id, command: command, state: &state)
        }
    }

    private func confirmWatch(
        _ id: UUID, command: WatchExperimentCommand, state: inout State
    ) throws -> Effect<Action> {
        guard state.watchReviewRequest == nil, !state.video.isSaving
        else { throw WatchExperimentError.phoneBusy }
        if state.watchPhotoRequest.map(recordID) == id, state.photo.recordID == id {
            state.watchReviewRequest = command
            return state.photo.isSaving ? .none : .send(.photo(.watchSaveRequested(id)))
        }
        if state.watchVideoRequest.map(recordID) == id, state.video.recordID == id {
            state.watchReviewRequest = command
            return .send(.video(.watchSaveRequested(id)))
        }
        throw WatchExperimentError.invalidState
    }

    private func cancelWatch(
        _ id: UUID, command: WatchExperimentCommand, state: inout State
    ) throws -> Effect<Action> {
        if state.watchPhotoRequest.map(recordID) == id,
           state.photo.requestedRecordID == id || state.photo.recordID == id {
            guard state.watchPhotoCancellationRequest == nil,
                  !state.photo.isSaving, !state.photo.isCapturing else {
                throw WatchExperimentError.phoneBusy
            }
            state.watchPhotoCancellationRequest = command
            return .send(.photo(.watchCancelRequested(id)))
        }
        if state.watchVideoRequest.map(recordID) == id, state.video.recordID == id,
           case .preview = state.video.phase {
            guard state.watchVideoCancellationRequest == nil, !state.video.isSaving else {
                throw WatchExperimentError.phoneBusy
            }
            state.watchVideoCancellationRequest = command
            return .send(.video(.watchCancelRequested(id)))
        }
        throw WatchExperimentError.invalidState
    }

    private func requireCamera(_ state: State) throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw WatchExperimentError.permissionDenied
        }
        guard state.canRequestCameraCapture else { throw WatchExperimentError.cameraUnavailable }
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
