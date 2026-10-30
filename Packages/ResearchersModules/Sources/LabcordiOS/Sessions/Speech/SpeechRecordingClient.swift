import ComposableArchitecture
import Foundation

public struct SpeechRecording: Equatable, Sendable {
    public let audioURL: URL
    public let transcript: String

    public init(audioURL: URL, transcript: String) {
        self.audioURL = audioURL
        self.transcript = transcript
    }
}

public enum SpeechRecordingEvent: Equatable, Sendable {
    case transcript(String)
    case finished(SpeechRecording)
    case failed(String)
}

public struct SpeechRecordingClient: Sendable {
    public var start: @Sendable () async throws -> AsyncStream<SpeechRecordingEvent>
    public var stop: @Sendable () async -> SpeechRecording?
    public var cancel: @Sendable () async -> Void

    public init(
        start: @escaping @Sendable () async throws -> AsyncStream<SpeechRecordingEvent>,
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
            start: { try await session.start() },
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
