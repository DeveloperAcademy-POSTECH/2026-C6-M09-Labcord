import Foundation
import LabcordShared
import LabcordWatchOS
import WatchConnectivity

extension WatchRecordingService {
    func updateVoiceLiveStatus(_ record: WatchRecordPresentation) {
        guard record.kind == .voice, record.startedAt != nil else { return }
        if record.phase == .capturing, recorder.activeRecording?.recordingID == record.id {
            if voiceStatusRecordID != record.id {
                voiceStatusTasks.values.forEach { $0.cancel() }
                voiceStatusTasks.removeAll()
                voiceStatusRecordID = record.id
            }
        }
        guard voiceStatusRecordID == record.id else { return }
        if record.phase == .capturing, voiceStatusTasks[record.id] != nil { return }
        refreshVoiceLiveStatus()
        guard !isTerminalVoiceStatus(record) else {
            voiceStatusTasks.removeValue(forKey: record.id)?.cancel()
            return
        }
        guard voiceStatusTasks[record.id] == nil else { return }
        voiceStatusTasks[record.id] = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.voiceStatusRecordID == record.id,
                      let current = self.records[record.id],
                      !self.isTerminalVoiceStatus(current) else { return }
                self.refreshVoiceLiveStatus()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    func refreshVoiceLiveStatus() {
        guard let id = voiceStatusRecordID, let record = records[id],
              let startedAt = record.startedAt,
              let session = connectivity.session, session.isReachable else { return }
        let isRecording = recorder.activeRecording?.recordingID == id
        let status = WatchVoiceLiveStatus(
            experimentID: record.experimentID, recordingID: record.id, startedAt: startedAt,
            sentAt: .now, isRecording: isRecording,
            phase: isRecording ? .recording : voiceStatusPhase(record),
            elapsedSeconds: isRecording ? nil : TimeInterval(record.elapsedSeconds)
        )
        guard let data = try? JSONEncoder().encode(status) else { return }
        session.sendMessage(
            [WatchVoiceLiveStatus.messageKey: data],
            replyHandler: { @Sendable _ in }, errorHandler: { @Sendable _ in }
        )
    }

    private func isTerminalVoiceStatus(_ record: WatchRecordPresentation) -> Bool {
        recorder.activeRecording?.recordingID != record.id
            && (record.phase == .saved || record.phase == .cancelled || record.phase == .failed)
    }

    private func voiceStatusPhase(_ record: WatchRecordPresentation) -> WatchRecordSnapshot.Phase {
        switch record.phase {
        case .starting, .capturing: .recording
        case .stopping, .transferring, .transcribing: .previewing
        case .review: .review
        case .saving: .saving
        case .saved: .saved
        case .failed: .failed
        case .cancelled: .cancelled
        }
    }
}
