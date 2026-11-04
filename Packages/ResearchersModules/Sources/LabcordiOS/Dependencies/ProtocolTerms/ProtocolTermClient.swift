import ComposableArchitecture
import CryptoKit
import Foundation
import FoundationModels
import OmniParser

nonisolated public struct ProtocolExtractedTerms: Equatable, Sendable {
    public var materials: [String]
    public var samples: [String]
    public var glossaryTerms: [String]
    public var units: [String]
    public var usedFallback: Bool

    public init(
        materials: [String] = [],
        samples: [String] = [],
        glossaryTerms: [String] = [],
        units: [String] = [],
        usedFallback: Bool = false
    ) {
        self.materials = materials
        self.samples = samples
        self.glossaryTerms = glossaryTerms
        self.units = units
        self.usedFallback = usedFallback
    }

    public var isEmpty: Bool {
        materials.isEmpty && samples.isEmpty && glossaryTerms.isEmpty && units.isEmpty
    }

    public var all: [String] { materials + samples + glossaryTerms + units }
}

nonisolated struct ProtocolTermLabels {
    var labels: [ProtocolTermLabel]
}

nonisolated struct ProtocolTermLabel {
    var term: String
    var category: Category

    @Generable
    enum Category {
        case material
        case sample
        case glossary
        case unit
    }
}

nonisolated public enum ProtocolTermProgress: Equatable, Sendable {
    case preparingExtraction
    case extractingCandidates
    case preparingRanking
    case rankingCandidates(Int)
    case rankingProgress(completed: Int, total: Int)
    case classifyingTerms(completed: Int, total: Int)
    case organizingTerms
}

nonisolated public enum ProtocolTermReviewCategory: String, Codable, Sendable {
    case material, sample, glossary, unit
}

nonisolated public struct ProtocolTermSourceSpan: Codable, Equatable, Sendable {
    public var start: Int
    public var end: Int
    public var blockIndex: Int

    public init(start: Int, end: Int, blockIndex: Int) {
        self.start = start
        self.end = end
        self.blockIndex = blockIndex
    }
}

nonisolated public struct ProtocolTermReviewRow: Codable, Equatable, Sendable {
    public var original: String
    public var surface: String
    public var category: ProtocolTermReviewCategory
    public var evidence: ProtocolTermSourceSpan?

    public init(
        original: String, surface: String, category: ProtocolTermReviewCategory,
        evidence: ProtocolTermSourceSpan? = nil
    ) {
        self.original = original
        self.surface = surface
        self.category = category
        self.evidence = evidence
    }
}

nonisolated public struct ProtocolTermReviewCheckpoint: Codable, Equatable, Sendable {
    public static let currentPolicyVersion = 1
    public var policyVersion: Int
    public var sourceHash: String
    public var candidatesHash: String
    public var rows: [ProtocolTermReviewRow]
    public var usedFallback: Bool

    public var processedCount: Int { rows.count }

    public init(terms: [String], source: String) {
        policyVersion = Self.currentPolicyVersion
        sourceHash = Self.hash(Data(source.utf8))
        candidatesHash = Self.candidateHash(terms)
        rows = []
        usedFallback = false
    }

    public func validate(terms: [String], source: String) throws {
        guard policyVersion == Self.currentPolicyVersion,
              sourceHash == Self.hash(Data(source.utf8)),
              candidatesHash == Self.candidateHash(terms), rows.count <= terms.count,
              zip(rows, terms).allSatisfy({ $0.original.unicodeScalars
                  .elementsEqual($1.unicodeScalars) }) else {
            throw ProtocolTermClassifier.ClassificationError.invalidCheckpoint
        }
        let sourceScalars = Array(source.unicodeScalars)
        for row in rows {
            guard !row.surface.isEmpty else {
                throw ProtocolTermClassifier.ClassificationError.invalidCheckpoint
            }
            if let span = row.evidence {
                guard span.start >= 0, span.end > span.start, span.end <= sourceScalars.count,
                      span.blockIndex >= 0,
                      sourceScalars[span.start..<span.end]
                        .elementsEqual(row.surface.unicodeScalars)
                else { throw ProtocolTermClassifier.ClassificationError.invalidCheckpoint }
            } else if !row.surface.unicodeScalars.elementsEqual(row.original.unicodeScalars) {
                throw ProtocolTermClassifier.ClassificationError.invalidCheckpoint
            }
        }
    }

    public var terms: ProtocolExtractedTerms {
        var groupedTerms = ProtocolExtractedTerms(usedFallback: usedFallback)
        var seenSurfaceBytes = Set<Data>()
        for row in rows where seenSurfaceBytes.insert(Data(row.surface.utf8)).inserted {
            switch row.category {
            case .material: groupedTerms.materials.append(row.surface)
            case .sample: groupedTerms.samples.append(row.surface)
            case .glossary: groupedTerms.glossaryTerms.append(row.surface)
            case .unit: groupedTerms.units.append(row.surface)
            }
        }
        return groupedTerms
    }

    private static func candidateHash(_ terms: [String]) -> String {
        hash((try? JSONEncoder().encode(terms)) ?? Data())
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated public struct ProtocolTermClient: Sendable {
    public typealias Progress = @Sendable (ProtocolTermProgress) async -> Void
    public typealias Checkpoint = @Sendable (ProtocolExtractedTerms) async throws -> Void
    public typealias ReviewCheckpoint = @Sendable (
        ProtocolTermReviewCheckpoint
    ) async throws -> Void
    public var reviewDocumentTerms: (@Sendable (
        [String], DocumentParseResult, ProtocolTermReviewCheckpoint?, Progress?, ReviewCheckpoint
    ) async throws -> ProtocolExtractedTerms)?
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
            let terms = try await ProtocolTermExtractor.shared.extract(
                from: text, progress: progress)
            try Task.checkCancellation()
            let document = DocumentParseResult(
                format: .txt,
                blocks: [DocumentBlock(kind: .paragraph, text: text, readingOrder: 0)],
                warnings: []
            )
            return try await ProtocolTermClassifier.reviewDocument(
                terms, document: document, progress: progress
            )
        }
        client.selectDocumentTerms = { document, progress in
            let terms = try await ProtocolTermExtractor.shared.extract(
                from: document.fullText, progress: progress
            )
            try Task.checkCancellation()
            return terms.filter { term in
                !term.isEmpty && document.blocks.contains { block in
                    block.kind != .table && block.kind != .image
                        && block.text.range(of: term, options: .literal) != nil
                }
            }
        }
        client.classifyDocumentTerms = { terms, text, seed, progress, checkpoint in
            try await ProtocolTermClassifier.classifyDocument(
                terms, context: text, seed: seed, progress: progress, checkpoint: checkpoint
            )
        }
        client.reviewDocumentTerms = { terms, document, seed, progress, checkpoint in
            try await ProtocolTermClassifier.reviewDocument(
                terms, document: document, seed: seed, progress: progress, checkpoint: checkpoint
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

extension ProtocolTermClassifier {
    public enum ClassificationError: Swift.Error {
        case modelNotReady
        case invalidCheckpoint
        case invalidCandidates
    }

    static func reviewSchema(_ terms: [String], surfaces: [[String]]) throws -> GenerationSchema {
        let category = DynamicGenerationSchema(name: "ProtocolReviewCategory", anyOf: [
            "material", "sample", "glossary", "unit"
        ])
        let properties = terms.enumerated().map { index, term in
            let supportedTermSurfaces = surfaces[index]
            let schema: DynamicGenerationSchema = supportedTermSurfaces.count > 1 ? .init(
                name: "ProtocolReviewRow\(index)", properties: [
                    .init(name: "surface", schema: .init(
                        name: "ProtocolReviewSurface\(index)", anyOf: supportedTermSurfaces)),
                    .init(name: "category", schema: .init(referenceTo: "ProtocolReviewCategory"))
                ]
            ) : .init(referenceTo: "ProtocolReviewCategory")
            return DynamicGenerationSchema.Property(name: term,
                description: "Review this exact original term: \(term).", schema: schema)
        }
        let rootSchema = DynamicGenerationSchema(
            name: "ProtocolTermReview", properties: properties)
        return try GenerationSchema(root: rootSchema, dependencies: [category])
    }

}
