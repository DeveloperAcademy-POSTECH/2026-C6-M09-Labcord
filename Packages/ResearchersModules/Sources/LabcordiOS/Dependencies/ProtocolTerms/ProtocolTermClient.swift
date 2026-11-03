import ComposableArchitecture
import Foundation
import OmniParser

/// 실제 추출·분류 작업에서 관찰한 현재 단계입니다. 예상 진행률을 뜻하지 않습니다.
nonisolated public enum ProtocolTermProgress: Equatable, Sendable {
    case preparingExtraction
    case extractingCandidates
    case preparingRanking
    case rankingCandidates(Int)
    case rankingProgress(completed: Int, total: Int)
    case classifyingTerms(completed: Int, total: Int)
    case organizingTerms
}

/// 파싱된 프로토콜 본문에서 용어를 추출(R117)하고 분류(Foundation Model)합니다.
nonisolated public struct ProtocolTermClient: Sendable {
    public typealias Progress = @Sendable (ProtocolTermProgress) async -> Void
    public typealias Checkpoint = @Sendable (ProtocolExtractedTerms) async throws -> Void
    public var selectDocumentTerms: @Sendable (
        DocumentParseResult, Progress?
    ) async throws -> [String]
    public var classifyDocumentTerms: @Sendable (
        [String], String, ProtocolExtractedTerms?, Progress?, Checkpoint
    ) async throws -> ProtocolExtractedTerms
    public var extract: @Sendable (String) async throws -> ProtocolExtractedTerms
    public var extractWithProgress: @Sendable (
        String, Progress?
    ) async throws -> ProtocolExtractedTerms

    public init(extract: @escaping @Sendable (String) async throws -> ProtocolExtractedTerms) {
        self.extract = extract
        selectDocumentTerms = { document, _ in try await extract(document.fullText).all }
        classifyDocumentTerms = { _, text, _, _, _ in try await extract(text) }
        extractWithProgress = { text, _ in try await extract(text) }
    }

    public init(
        extractWithProgress: @escaping @Sendable (
            String, Progress?
        ) async throws -> ProtocolExtractedTerms
    ) {
        self.extractWithProgress = extractWithProgress
        selectDocumentTerms = { document, progress in
            try await extractWithProgress(document.fullText, progress).all
        }
        classifyDocumentTerms = { _, text, _, progress, _ in
            try await extractWithProgress(text, progress)
        }
        extract = { text in try await extractWithProgress(text, nil) }
    }
}

extension ProtocolTermClient: DependencyKey {
    nonisolated public static let liveValue: ProtocolTermClient = {
        var client = ProtocolTermClient { text, progress in
            let terms = try await R117TermExtractor.shared.extract(from: text, progress: progress)
            try Task.checkCancellation()
            return try await ProtocolTermClassifier.classifyDocument(
                terms, context: text, progress: progress
            )
        }
        client.selectDocumentTerms = { document, progress in
            let terms = try await R117TermExtractor.shared.extract(
                from: document.fullText, progress: progress
            )
            return try ProtocolDocumentTermCleaner.clean(terms, document: document)
        }
        client.classifyDocumentTerms = { terms, text, seed, progress, checkpoint in
            try await ProtocolTermClassifier.classifyDocument(
                terms, context: text, seed: seed, progress: progress, checkpoint: checkpoint
            )
        }
        return client
    }()

    nonisolated public static let testValue = ProtocolTermClient { _ in ProtocolExtractedTerms() }
    nonisolated public static let previewValue = testValue
}

public extension DependencyValues {
    var protocolTermClient: ProtocolTermClient {
        get { self[ProtocolTermClient.self] }
        set { self[ProtocolTermClient.self] = newValue }
    }
}
