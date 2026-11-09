import Foundation
import LabcordShared

struct WatchRecordingScreenState {
    private(set) var recording: WatchScreenRecording?
    private var unsettled: [UUID: UUID] = [:]
    private var terminalPhases: [UUID: WatchRecordSnapshot.Phase] = [:]

    func hasUnsettledRecording(in experimentID: UUID?) -> Bool {
        guard let experimentID else { return !unsettled.isEmpty }
        return unsettled.values.contains(experimentID)
    }

    mutating func dismissFinishedRecording() {
        guard let recording, [.saved, .cancelled].contains(recording.phase) else { return }
        self.recording = nil
    }

    mutating func receive(_ status: WatchVoiceLiveStatus) {
        guard terminalPhases[status.recordingID] == nil,
              status.elapsedSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true else { return }
        unsettled[status.recordingID] = status.experimentID
        let phase = status.phase ?? (status.isRecording ? .recording : .previewing)
        let displayedPhase: WatchRecordSnapshot.Phase = [.saved, .cancelled].contains(phase)
            ? .saving : phase
        update(WatchScreenRecording(
            id: status.recordingID, experimentID: status.experimentID,
            origin: .watch, kind: .audio, phase: displayedPhase, startedAt: status.startedAt,
            elapsedSeconds: status.elapsedSeconds ?? elapsedSeconds(for: status.recordingID)
        ))
    }

    mutating func receive(_ record: WatchRecordSnapshot, elapsedSeconds: TimeInterval? = nil) {
        guard record.kind == .audio, let experimentID = record.experimentID,
              elapsedSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true else { return }
        let terminal = record.phase == .saved || record.phase == .cancelled
        if terminal {
            unsettled.removeValue(forKey: record.id)
            terminalPhases[record.id] = record.phase
        } else {
            guard terminalPhases[record.id] == nil else { return }
            unsettled[record.id] = experimentID
        }
        update(WatchScreenRecording(
            id: record.id, experimentID: experimentID, origin: .watch, kind: .audio,
            phase: record.phase, startedAt: record.startedAt,
            elapsedSeconds: elapsedSeconds ?? self.elapsedSeconds(for: record.id)
        ))
    }

    private func elapsedSeconds(for id: UUID) -> TimeInterval? {
        recording?.id == id ? recording?.elapsedSeconds : nil
    }

    private mutating func update(_ candidate: WatchScreenRecording) {
        if let current = recording {
            if current.id != candidate.id,
               (candidate.startedAt ?? .distantPast) < (current.startedAt ?? .distantPast) {
                return
            }
            if current.id == candidate.id {
                let earlier: [WatchRecordSnapshot.Phase] = [.capturing, .recording, .previewing]
                if current.phase == .saving, earlier.contains(candidate.phase)
                    || candidate.phase == .review { return }
                if current.phase == .review, earlier.contains(candidate.phase) { return }
            }
        }
        recording = candidate
    }
}
