import Foundation
import LabcordShared

struct WatchRecordingScreenState {
    private(set) var recording: WatchScreenRecording?
    private var unsettled: [UUID: UUID] = [:]
    private var activeCaptures: [UUID: (experimentID: UUID, expiresAt: Date)] = [:]
    private var terminalPhases: [UUID: WatchRecordSnapshot.Phase] = [:]

    func hasUnsettledRecording(in experimentID: UUID?, at now: Date = .now) -> Bool {
        unsettled.values.contains { experimentID == nil || $0 == experimentID }
            || activeCaptures.values.contains {
                $0.expiresAt > now && (experimentID == nil || $0.experimentID == experimentID)
            }
    }

    mutating func expireCaptures(at now: Date) {
        guard activeCaptures.values.contains(where: { $0.expiresAt <= now }) else { return }
        activeCaptures = activeCaptures.filter { $0.value.expiresAt > now }
        if let recording, recording.phase == .recording,
           activeCaptures[recording.id] == nil, unsettled[recording.id] == nil {
            self.recording = nil
        }
    }

    mutating func dismissFinishedRecording() {
        guard let recording, [.saved, .cancelled].contains(recording.phase) else { return }
        self.recording = nil
    }

    mutating func receive(_ status: WatchVoiceLiveStatus) {
        guard terminalPhases[status.recordingID] == nil,
              status.elapsedSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true else { return }
        let phase = status.phase ?? (status.isRecording ? .recording : .previewing)
        guard phase != .cancelled, phase != .saved else { return }
        if status.isRecording {
            guard unsettled[status.recordingID] == nil else {
                // The inbox already keeps this recording protected.
                return
            }
            activeCaptures[status.recordingID] = (
                status.experimentID, status.sentAt.addingTimeInterval(3)
            )
        } else {
            activeCaptures.removeValue(forKey: status.recordingID)
            if phase != .failed { unsettled[status.recordingID] = status.experimentID }
        }
        update(WatchScreenRecording(
            id: status.recordingID, experimentID: status.experimentID,
            origin: .watch, kind: .audio, phase: phase, startedAt: status.startedAt,
            elapsedSeconds: status.elapsedSeconds ?? elapsedSeconds(for: status.recordingID)
        ))
    }

    mutating func receive(_ record: WatchRecordSnapshot, elapsedSeconds: TimeInterval? = nil) {
        guard record.kind == .audio, let experimentID = record.experimentID,
              elapsedSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true else { return }
        guard terminalPhases[record.id] == nil else { return }
        if record.phase == .saved || record.phase == .cancelled {
            unsettled.removeValue(forKey: record.id)
            activeCaptures.removeValue(forKey: record.id)
            terminalPhases[record.id] = record.phase
        } else if record.originalRetained == true {
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
