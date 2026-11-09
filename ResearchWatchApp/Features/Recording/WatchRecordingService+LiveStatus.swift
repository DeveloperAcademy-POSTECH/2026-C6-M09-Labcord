import Foundation
import LabcordShared
import LabcordWatchOS
import WatchConnectivity

extension WatchRecordingService {
    func updateVoiceLiveStatus(_ record: WatchRecordPresentation) {
        guard record.kind == .voice, let startedAt = record.startedAt else { return }
        if record.phase == .capturing, recorder.activeRecording?.recordingID == record.id {
            guard voiceStatusTasks[record.id] == nil else { return }
            voiceStatusTasks[record.id] = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, let current = self.records[record.id],
                          current.phase == .capturing,
                          self.recorder.activeRecording?.recordingID == record.id else { return }
                    self.sendVoiceLiveStatus(current, startedAt: startedAt, isRecording: true)
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
        } else if let task = voiceStatusTasks.removeValue(forKey: record.id) {
            task.cancel()
            sendVoiceLiveStatus(record, startedAt: startedAt, isRecording: false)
        }
    }

    private func sendVoiceLiveStatus(
        _ record: WatchRecordPresentation, startedAt: Date, isRecording: Bool
    ) {
        guard let session = connectivity.session, session.isReachable else { return }
        let status = WatchVoiceLiveStatus(
            experimentID: record.experimentID, recordingID: record.id, startedAt: startedAt,
            sentAt: .now, isRecording: isRecording
        )
        guard let data = try? JSONEncoder().encode(status) else { return }
        session.sendMessage(
            [WatchVoiceLiveStatus.messageKey: data], replyHandler: { _ in }, errorHandler: { _ in }
        )
    }
}
