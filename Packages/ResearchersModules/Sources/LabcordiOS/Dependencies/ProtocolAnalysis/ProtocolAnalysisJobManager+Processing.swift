import Foundation
import OmniParser

extension ProtocolAnalysisJobManager {
    func process(
        _ input: ProtocolAnalysisJobInput, id: UUID, attempt: UUID
    ) async throws {
        try check(id: id, attempt: attempt)
        let key = input.id.uuidString
        if record?.documents[key] == nil {
            let items = try await parser.parseReportingProgress([
                ProtocolAnalysisInput(id: input.id, url: input.url)
            ]) { inputID, value in
                await self.progress(.reading(inputID, value), id: id, attempt: attempt)
            }
            try check(id: id, attempt: attempt)
            guard items.count == 1, let item = items.first, item.id == input.id else {
                throw CocoaError(.coderReadCorrupt)
            }
            guard var value = record else { throw CocoaError(.coderReadCorrupt) }
            let succeeded = try value.recordOutcome(item.outcome, key: key)
            record = value
            try persist()
            if !succeeded { return }
        }
        guard let saved = record?.documents[key] else {
            throw CocoaError(.coderReadCorrupt)
        }
        let document = try saved.restored()
        if record?.selected[key] == nil {
            let terms = try await termClient.selectDocumentTerms(document) { value in
                await self.progress(.terms(input.id, value), id: id, attempt: attempt)
            }
            try check(id: id, attempt: attempt)
            record?.selected[key] = terms
            try persist()
        }
        if record?.finished.contains(key) != true {
            let selected = record?.selected[key] ?? []
            let terms = try await classify(
                selected, document: document, input: input.id, id: id, attempt: attempt
            )
            try check(id: id, attempt: attempt)
            record?.classified[key] = ProtocolAnalysisSavedTerms(terms)
            record?.finished.insert(key)
            try persist()
        }
    }

    private func classify(
        _ selected: [String], document: DocumentParseResult, input: UUID,
        id: UUID, attempt: UUID
    ) async throws -> ProtocolExtractedTerms {
        let key = input.uuidString
        let report: ProtocolTermClient.Progress = { value in
            await self.progress(.terms(input, value), id: id, attempt: attempt)
        }
        if let policy = record?.reviewPolicyVersion, let review = termClient.reviewDocumentTerms {
            guard policy == ProtocolTermReviewCheckpoint.currentPolicyVersion else {
                throw ProtocolTermClassifier.ClassificationError.invalidCheckpoint
            }
            return try await review(selected, document, record?.reviews?[key], report) { partial in
                try await self.saveReview(partial, key: key, id: id, attempt: attempt)
            }
        } else {
            let seed = record?.classified[key]?.restored
            return try await termClient.classifyDocumentTerms(
                selected, document.fullText, seed, report
            ) { partial in
                try await self.saveClassification(partial, key: key, id: id, attempt: attempt)
            }
        }
    }

    private func saveReview(
        _ review: ProtocolTermReviewCheckpoint, key: String, id: UUID, attempt: UUID
    ) throws {
        try check(id: id, attempt: attempt)
        guard let selected = record?.selected[key],
              let document = record?.documents[key] else {
            throw ProtocolTermClassifier.ClassificationError.invalidCheckpoint
        }
        try review.validate(terms: selected, source: document.restored().fullText)
        if record?.reviews == nil { record?.reviews = [:] }
        record?.reviews?[key] = review
        try persist()
    }

    private func saveClassification(
        _ terms: ProtocolExtractedTerms, key: String, id: UUID, attempt: UUID
    ) throws {
        try check(id: id, attempt: attempt)
        record?.classified[key] = ProtocolAnalysisSavedTerms(terms)
        try persist()
    }
}
