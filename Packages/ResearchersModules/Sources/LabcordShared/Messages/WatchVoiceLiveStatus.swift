import Foundation

public struct WatchVoiceLiveStatus: Codable, Equatable, Sendable {
    public static let messageKey = "labcordVoiceLiveStatus"

    public let experimentID: UUID
    public let recordingID: UUID
    public let startedAt: Date
    public let sentAt: Date
    public let isRecording: Bool

    public init(
        experimentID: UUID, recordingID: UUID, startedAt: Date, sentAt: Date, isRecording: Bool
    ) {
        self.experimentID = experimentID
        self.recordingID = recordingID
        self.startedAt = startedAt
        self.sentAt = sentAt
        self.isRecording = isRecording
    }
}
