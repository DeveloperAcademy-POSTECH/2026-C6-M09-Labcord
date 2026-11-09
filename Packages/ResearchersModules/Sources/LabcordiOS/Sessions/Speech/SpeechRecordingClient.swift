import ComposableArchitecture
import Foundation
import Speech

public struct SpeechLanguageModelHint: Equatable, Sendable {
    public var languageModel: URL
    public var vocabulary: URL

    public init(languageModel: URL, vocabulary: URL) {
        self.languageModel = languageModel
        self.vocabulary = vocabulary
    }

    func makeConfiguration() -> SFSpeechLanguageModel.Configuration {
        SFSpeechLanguageModel.Configuration(
            languageModel: languageModel, vocabulary: vocabulary
        )
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
    private var startOperation: @Sendable (
        UUID, [String], [String: String], [String], SpeechLanguageModelHint?
    ) async throws -> AsyncStream<SpeechRecordingEvent>
    public var stop: @Sendable () async -> SpeechRecording?
    public var cancel: @Sendable () async -> Void

    public init(
        start: @escaping @Sendable (
            UUID, [String], [String: String], [String], SpeechLanguageModelHint?
        ) async throws -> AsyncStream<SpeechRecordingEvent>,
        stop: @escaping @Sendable () async -> SpeechRecording?,
        cancel: @escaping @Sendable () async -> Void
    ) {
        self.startOperation = start
        self.stop = stop
        self.cancel = cancel
    }

    public func start(
        experimentID: UUID,
        contextualStrings: [String],
        phoneticReplacements: [String: String],
        units: [String],
        languageModelHint: SpeechLanguageModelHint?
    ) async throws -> AsyncStream<SpeechRecordingEvent> {
        try await startOperation(
            experimentID, contextualStrings, phoneticReplacements, units, languageModelHint
        )
    }
}

extension SpeechRecordingClient: DependencyKey {
    public static let liveValue: SpeechRecordingClient = {
        let session = SpeechRecordingSession()
        return SpeechRecordingClient(
            start: { experimentID, contextualStrings, phoneticReplacements, units, hint in
                try await session.start(
                    experimentID: experimentID, contextualStrings: contextualStrings,
                    phoneticReplacements: phoneticReplacements, units: units,
                    languageModelHint: hint
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
