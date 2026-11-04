import ComposableArchitecture
import Foundation
import OmniParser

nonisolated public struct ProtocolAnalysisInput: Equatable, Sendable {
    public let id: UUID
    public let url: URL

    public init(id: UUID, url: URL) {
        self.id = id
        self.url = url
    }
}

nonisolated public enum ProtocolAnalysisOutcome: Equatable, Sendable {
    case success(DocumentParseResult)
    case failure(DocumentParsingError)
}

nonisolated public struct ProtocolAnalysisItem: Equatable, Sendable {
    public let id: UUID
    public let outcome: ProtocolAnalysisOutcome

    public var extractedText: String? {
        guard case let .success(document) = outcome else { return nil }
        return document.fullText
    }

    public var hasWarnings: Bool {
        guard case let .success(document) = outcome else { return false }
        return !document.warnings.isEmpty
    }
}

nonisolated public enum ProtocolReadingPhase: String, Equatable, Sendable {
    case identifying, extracting, recognizingText, completed, failed, cancelled
}

nonisolated public struct ProtocolAnalysisClient: Sendable {
    public typealias Progress = @Sendable (UUID, ProtocolReadingPhase) -> Void

    public var parse: @Sendable (
        [ProtocolAnalysisInput], Progress?
    ) async throws -> [ProtocolAnalysisItem]

    public func parseReportingProgress(
        _ inputs: [ProtocolAnalysisInput],
        progress: @escaping @Sendable (UUID, ProtocolReadingPhase) async -> Void
    ) async throws -> [ProtocolAnalysisItem] {
        let (events, continuation) = AsyncStream<(UUID, ProtocolReadingPhase)>.makeStream()
        let updates = Task {
            for await (inputID, phase) in events { await progress(inputID, phase) }
        }
        do {
            let result = try await parse(inputs) { inputID, phase in
                continuation.yield((inputID, phase))
            }
            continuation.finish()
            await updates.value
            return result
        } catch {
            continuation.finish()
            await updates.value
            throw error
        }
    }

    public init(
        parse: @escaping @Sendable (
            [ProtocolAnalysisInput], Progress?
        ) async throws -> [ProtocolAnalysisItem]
    ) {
        self.parse = parse
    }
}

extension ProtocolAnalysisClient: DependencyKey {
    nonisolated public static let liveValue = ProtocolAnalysisClient { inputs, progress in
        let results = try await DocumentParser.parseBatch(
            inputs.map { .url($0.url) },
            options: DocumentParserOptions(performOCR: true)
        ) { event in
            guard inputs.indices.contains(event.inputIndex) else { return }
            guard let phase = ProtocolReadingPhase(rawValue: event.phase.rawValue) else { return }
            progress?(inputs[event.inputIndex].id, phase)
        }
        try Task.checkCancellation()
        return zip(inputs, results).map { input, result in
            let outcome: ProtocolAnalysisOutcome
            switch result {
            case let .success(document): outcome = .success(document)
            case let .failure(error): outcome = .failure(error)
            }
            return ProtocolAnalysisItem(id: input.id, outcome: outcome)
        }
    }
}

public extension DependencyValues {
    var protocolAnalysisClient: ProtocolAnalysisClient {
        get { self[ProtocolAnalysisClient.self] }
        set { self[ProtocolAnalysisClient.self] = newValue }
    }
}
