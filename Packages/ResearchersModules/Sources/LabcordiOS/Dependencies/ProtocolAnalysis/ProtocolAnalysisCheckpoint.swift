import Foundation
import OmniParser

nonisolated public struct ProtocolAnalysisJobInput: Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let isPhoto: Bool

    public init(id: UUID, url: URL, name: String, isPhoto: Bool) {
        self.id = id
        self.url = url
        self.name = name
        self.isPhoto = isPhoto
    }
}

nonisolated public enum ProtocolAnalysisJobStatus: String, Codable, Sendable {
    case queued, running, paused, completed, cancelled, failed
}

nonisolated public enum ProtocolAnalysisJobPhase: Equatable, Sendable {
    case queued
    case reading(UUID, ProtocolReadingPhase)
    case terms(UUID, ProtocolTermProgress)
}

nonisolated public struct ProtocolAnalysisJobSnapshot: Equatable, Sendable {
    public let id: UUID
    public let inputs: [ProtocolAnalysisJobInput]
    public let status: ProtocolAnalysisJobStatus
    public let phase: ProtocolAnalysisJobPhase
    public let startedAt: Date
    public let message: String?
    public let backgroundAvailable: Bool
    public let results: [ProtocolAnalysisItem]
    public let terms: [UUID: ProtocolExtractedTerms]
}

nonisolated struct ProtocolAnalysisSavedDocument: Codable {
    var format: String
    var blocks: [Block]
    var warnings: [Warning]

    init(_ document: DocumentParseResult) {
        format = document.format.rawValue
        blocks = document.blocks.map(Block.init)
        warnings = document.warnings.map(Warning.init)
    }

    func restored() throws -> DocumentParseResult {
        guard let format = DocumentFormat(rawValue: format) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return try DocumentParseResult(
            format: format, blocks: blocks.map { try $0.restored() },
            warnings: warnings.map { try $0.restored() }
        )
    }

    struct Location: Codable {
        var part: String?
        var page: Int?
        var row: Int?
        var column: Int?
        var paragraph: Int?
        var bounds: CGRect?
        var rowSpan: Int?
        var columnSpan: Int?

        init(_ value: DocumentLocation) {
            part = value.part
            page = value.page
            row = value.row
            column = value.column
            paragraph = value.paragraph
            bounds = value.bounds
            rowSpan = value.rowSpan
            columnSpan = value.columnSpan
        }

        var restored: DocumentLocation {
            DocumentLocation(
                part: part, page: page, row: row, column: column, paragraph: paragraph,
                bounds: bounds, rowSpan: rowSpan, columnSpan: columnSpan
            )
        }
    }

    struct Block: Codable {
        var kind: String
        var text: String
        var readingOrder: Int
        var location: Location
        var confidence: Float?
        var originalText: String?

        init(_ value: DocumentBlock) {
            kind = value.kind.rawValue
            text = value.text
            readingOrder = value.readingOrder
            location = Location(value.location)
            confidence = value.ocrConfidence
            originalText = value.ocrOriginalText
        }

        func restored() throws -> DocumentBlock {
            guard let kind = DocumentBlockKind(rawValue: kind) else {
                throw CocoaError(.coderReadCorrupt)
            }
            return DocumentBlock(
                kind: kind, text: text, readingOrder: readingOrder, location: location.restored,
                ocrConfidence: confidence, ocrOriginalText: originalText
            )
        }
    }

    struct Warning: Codable {
        var code: String
        var message: String
        var location: Location?

        init(_ value: DocumentWarning) {
            code = value.code.rawValue
            message = value.message
            location = value.location.map(Location.init)
        }

        func restored() throws -> DocumentWarning {
            guard let code = DocumentWarningCode(rawValue: code) else {
                throw CocoaError(.coderReadCorrupt)
            }
            return DocumentWarning(code: code, message: message, location: location?.restored)
        }
    }
}

nonisolated struct ProtocolAnalysisSavedTerms: Codable {
    var materials: [String]
    var samples: [String]
    var glossary: [String]
    var units: [String]
    var usedFallback: Bool

    init(_ terms: ProtocolExtractedTerms) {
        materials = terms.materials
        samples = terms.samples
        glossary = terms.glossaryTerms
        units = terms.units
        usedFallback = terms.usedFallback
    }

    var restored: ProtocolExtractedTerms {
        ProtocolExtractedTerms(
            materials: materials, samples: samples, glossaryTerms: glossary,
            units: units, usedFallback: usedFallback
        )
    }
}

nonisolated struct ProtocolAnalysisJobRecord: Codable {
    var version = 1
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var runStartedAt: Date?
    var status: ProtocolAnalysisJobStatus
    var message: String?
    var inputs: [Input]
    var documents: [String: ProtocolAnalysisSavedDocument] = [:]
    var failures: [String: ProtocolAnalysisSavedFailure]?
    var selected: [String: [String]] = [:]
    var classified: [String: ProtocolAnalysisSavedTerms] = [:]
    var finished: Set<String> = []
    var reviewPolicyVersion: Int?
    var reviews: [String: ProtocolTermReviewCheckpoint]?

    mutating func recordOutcome(_ outcome: ProtocolAnalysisOutcome, key: String) throws -> Bool {
        switch outcome {
        case let .success(document):
            documents[key] = ProtocolAnalysisSavedDocument(document)
            failures?.removeValue(forKey: key)
            return true
        case let .failure(error):
            if error == .cancelled { throw CancellationError() }
            if failures == nil { failures = [:] }
            failures?[key] = ProtocolAnalysisSavedFailure(error)
            return false
        }
    }

    func snapshot(
        inputs: [ProtocolAnalysisJobInput], phase: ProtocolAnalysisJobPhase,
        backgroundAvailable: Bool
    ) throws -> ProtocolAnalysisJobSnapshot {
        let results = try self.inputs.compactMap { input -> ProtocolAnalysisItem? in
            let key = input.id.uuidString
            if let value = documents[key] {
                return try ProtocolAnalysisItem(id: input.id, outcome: .success(value.restored()))
            }
            if let failure = failures?[key] {
                return ProtocolAnalysisItem(id: input.id, outcome: .failure(failure.restored))
            }
            return nil
        }
        var terms: [UUID: ProtocolExtractedTerms] = [:]
        for input in self.inputs where finished.contains(input.id.uuidString) {
            terms[input.id] = classified[input.id.uuidString]?.restored
        }
        return ProtocolAnalysisJobSnapshot(
            id: id, inputs: inputs, status: status, phase: phase,
            startedAt: runStartedAt ?? createdAt, message: message,
            backgroundAvailable: backgroundAvailable, results: results, terms: terms
        )
    }

    struct Input: Codable {
        var id: UUID
        var fileName: String
        var name: String
        var isPhoto: Bool
    }
}
