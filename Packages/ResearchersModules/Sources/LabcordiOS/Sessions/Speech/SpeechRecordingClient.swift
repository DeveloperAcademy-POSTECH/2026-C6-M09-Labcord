import ComposableArchitecture
import Foundation

public struct SpeechRecording: Equatable, Sendable {
    public let audioURL: URL
    public let transcript: String
    public let transcriptionIncomplete: Bool
    public let captureInterrupted: Bool

    public init(
        audioURL: URL, transcript: String, transcriptionIncomplete: Bool = false,
        captureInterrupted: Bool = false
    ) {
        self.audioURL = audioURL
        self.transcript = transcript
        self.transcriptionIncomplete = transcriptionIncomplete
        self.captureInterrupted = captureInterrupted
    }
}

public enum SpeechRecordingEvent: Equatable, Sendable {
    case transcript(String)
    case transcriptionUnavailable
    case finished(SpeechRecording)
    case interrupted(SpeechRecording, String)
    case failed(String)
}

public struct SpeechRecordingClient: Sendable {
    public var start: @Sendable (
        UUID, [String]
    ) async throws -> AsyncStream<SpeechRecordingEvent>
    public var stop: @Sendable () async -> SpeechRecording?
    public var cancel: @Sendable () async -> Void

    public init(
        start: @escaping @Sendable (
            UUID, [String]
        ) async throws -> AsyncStream<SpeechRecordingEvent>,
        stop: @escaping @Sendable () async -> SpeechRecording?,
        cancel: @escaping @Sendable () async -> Void
    ) {
        self.start = start
        self.stop = stop
        self.cancel = cancel
    }
}

extension SpeechRecordingClient: DependencyKey {
    public static let liveValue: SpeechRecordingClient = {
        let session = SpeechRecordingSession()
        return SpeechRecordingClient(
            start: { experimentID, contextualStrings in
                try await session.start(
                    experimentID: experimentID, contextualStrings: contextualStrings
                )
            },
            stop: { await session.stop() },
            cancel: { await session.cancel() }
        )
    }()
}

extension DependencyValues {
    public var speechRecordingClient: SpeechRecordingClient {
        get { self[SpeechRecordingClient.self] }
        set { self[SpeechRecordingClient.self] = newValue }
    }
}
