import Foundation
import LabcordiOS
import LabcordShared

extension ExperimentSessionFeature.State {
    var currentScreenRecording: WatchScreenRecording? {
        if voice.phase != .hidden { return voiceScreenRecording }
        if let photo = photoScreenRecording { return photo }
        return videoScreenRecording
    }

    private var voiceScreenRecording: WatchScreenRecording {
        let phase: WatchRecordSnapshot.Phase
        if voice.isSaving {
            phase = .saving
        } else if voice.saveError != nil || voice.recording?.captureInterrupted == true {
            phase = .failed
        } else {
            switch voice.phase {
            case .starting: phase = .capturing
            case .recording: phase = .recording
            case .stopping: phase = .capturing
            case .finished: phase = .review
            case .hidden: phase = .cancelled
            }
        }
        return .init(
            id: voice.sessionID, experimentID: experimentID, origin: .phone, kind: .audio,
            phase: phase, startedAt: voice.recordedAt, elapsedSeconds: voiceScreenElapsed
        )
    }

    private var photoScreenRecording: WatchScreenRecording? {
        let photo = capture.photo
        guard let id = photo.recordID ?? photo.requestedRecordID else { return nil }
        let phase: WatchRecordSnapshot.Phase
        if photo.isSaving {
            phase = .saving
        } else if photo.saveError != nil {
            phase = .failed
        } else if photo.capturedData != nil {
            phase = .review
        } else {
            phase = .capturing
        }
        return .init(
            id: id, experimentID: experimentID, origin: .phone, kind: .photo, phase: phase,
            startedAt: photo.scheduledAt ?? photo.recordedAt,
            countdownEndsAt: photo.countdownEndAt
        )
    }

    private var videoScreenRecording: WatchScreenRecording? {
        let video = capture.video
        guard video.phase != .idle else { return nil }
        let phase: WatchRecordSnapshot.Phase
        let startedAt: Date?
        switch video.phase {
        case .idle: return nil
        case .starting:
            phase = .capturing
            startedAt = nil
        case let .recording(date):
            phase = .recording
            startedAt = date
        case .preview:
            phase = video.isSaving ? .saving : video.saveError != nil ? .failed
                : video.hasPlaybackFinished ? .review : .previewing
            startedAt = lastScreenRecording?.kind == .video
                ? lastScreenRecording?.startedAt : video.recordedAt
        }
        return .init(
            id: video.requestedRecordID ?? video.recordID ?? video.sessionID,
            experimentID: experimentID, origin: .phone, kind: .video,
            phase: phase, startedAt: startedAt, elapsedSeconds: videoScreenElapsed
        )
    }

    private mutating func updateScreenElapsed(at date: Date) {
        if voice.phase == .starting || voice.phase == .recording {
            voiceScreenElapsed = nil
        } else if voice.phase == .stopping || voice.phase == .finished, voiceScreenElapsed == nil,
                  let startedAt = voice.recordedAt {
            voiceScreenElapsed = max(0, date.timeIntervalSince(startedAt))
        }
        switch capture.video.phase {
        case .starting, .recording:
            videoScreenElapsed = nil
        case .preview:
            if videoScreenElapsed == nil, lastScreenRecording?.kind == .video,
               let startedAt = lastScreenRecording?.startedAt {
                videoScreenElapsed = max(0, date.timeIntervalSince(startedAt))
            }
        case .idle:
            break
        }
    }

    mutating func updateScreenRecording(
        action: ExperimentSessionFeature.Action, at date: Date = .now
    ) {
        updateScreenElapsed(at: date)
        if let current = currentScreenRecording {
            lastScreenRecording = current
            return
        }
        guard let previous = lastScreenRecording else { return }
        let phase: WatchRecordSnapshot.Phase?
        switch action {
        case let .voice(.saved(id)) where voice.lastSavedRecordID == id,
             let .capture(.photo(.saved(id))) where previous.id == id,
             let .capture(.video(.saved(id))) where previous.id == id:
            phase = .saved
        case .voice(.startFailed), .voice(.event(_, .failed)),
             .capture(.photo(.captureFailed)), .capture(.video(.recordingFailed)):
            phase = .failed
        case .voice(.retakeRequested), .capture(.photo(.retakeRequested)),
             .capture(.photo(.cancelGesture)), .capture(.video(.cancelCleanupFinished)):
            phase = .cancelled
        default:
            phase = nil
        }
        guard let phase else { return }
        lastScreenRecording = .init(
            id: previous.id, experimentID: previous.experimentID, origin: previous.origin,
            kind: previous.kind, phase: phase, startedAt: previous.startedAt,
            elapsedSeconds: previous.elapsedSeconds
        )
    }
}
