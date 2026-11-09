import Foundation

public struct WatchVoiceLiveStatus: Codable, Equatable, Sendable {
    public static let messageKey = "labcordVoiceLiveStatus"

    public let experimentID: UUID
    public let recordingID: UUID
    public let startedAt: Date
    public let sentAt: Date
    public let isRecording: Bool
    public let phase: WatchRecordSnapshot.Phase?
    public let elapsedSeconds: TimeInterval?

    public init(
        experimentID: UUID, recordingID: UUID, startedAt: Date, sentAt: Date, isRecording: Bool,
        phase: WatchRecordSnapshot.Phase? = nil, elapsedSeconds: TimeInterval? = nil
    ) {
        self.experimentID = experimentID
        self.recordingID = recordingID
        self.startedAt = startedAt
        self.sentAt = sentAt
        self.isRecording = isRecording
        self.phase = phase
        self.elapsedSeconds = elapsedSeconds
    }
}
