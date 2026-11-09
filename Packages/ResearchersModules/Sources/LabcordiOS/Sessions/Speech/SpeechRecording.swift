import Foundation

public struct SpeechRecording: Equatable, Sendable {
    public let recordingID: UUID
    public let audioURL: URL
    public let transcript: String
    public let transcriptionIncomplete: Bool
    public let captureInterrupted: Bool

    public init(
        recordingID: UUID, audioURL: URL, transcript: String,
        transcriptionIncomplete: Bool = false, captureInterrupted: Bool = false
    ) {
        self.recordingID = recordingID
        self.audioURL = audioURL
        self.transcript = transcript
        self.transcriptionIncomplete = transcriptionIncomplete
        self.captureInterrupted = captureInterrupted
    }
}
