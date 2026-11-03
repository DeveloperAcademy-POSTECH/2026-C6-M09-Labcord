import CoreML
import Foundation

nonisolated final class R117Encoder {
    struct Document: Sendable {
        let offsets: [Range<Int>]
        let vectors: [[Double]]
        private let hasOrderedOffsets: Bool

        init(offsets: [Range<Int>], vectors: [[Double]]) {
            self.offsets = offsets
            self.vectors = vectors
            hasOrderedOffsets = zip(offsets, offsets.dropFirst()).allSatisfy { previous, next in
                previous.lowerBound <= next.lowerBound && previous.upperBound <= next.upperBound
            }
        }

        func pooled(in range: Range<Int>) throws -> [Float] {
            let overlaps = overlappingIndices(in: range).compactMap { index -> (Int, Int)? in
                let offset = offsets[index]
                let weight = max(0, min(offset.upperBound, range.upperBound)
                    - max(offset.lowerBound, range.lowerBound))
                return weight > 0 ? (index, weight) : nil
            }
            let total = overlaps.reduce(0) { $0 + $1.1 }
            guard total > 0 else { throw R117RuntimeError.uncoveredSource }
            var output = Array(repeating: 0.0, count: 384)
            for (index, weight) in overlaps {
                let scale = Double(Float(weight) / Float(total))
                for column in 0..<384 { output[column] += vectors[index][column] * scale }
            }
            return output.map(Float.init)
        }

        private func overlappingIndices(in range: Range<Int>) -> Range<Int> {
            guard hasOrderedOffsets else { return offsets.indices }
            guard !range.isEmpty else { return 0..<0 }
            let lower = firstOffset { $0.upperBound > range.lowerBound }
            let upper = firstOffset { $0.lowerBound >= range.upperBound }
            return lower..<upper
        }

        private func firstOffset(where predicate: (Range<Int>) -> Bool) -> Int {
            var lower = 0
            var upper = offsets.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if predicate(offsets[middle]) {
                    upper = middle
                } else {
                    lower = middle + 1
                }
            }
            return lower
        }

        func validateCoverage(text: String, range: Range<Int>) throws {
            let scalars = Array(text.unicodeScalars)
            guard range.lowerBound >= 0, range.upperBound <= scalars.count, !range.isEmpty else {
                throw R117RuntimeError.invalidCandidate
            }
            for position in range where !scalars[position].properties.isWhitespace {
                let scalar = scalars[position]
                if scalar.properties.generalCategory == .control { continue }
                guard offsets.contains(where: { $0.contains(position) }) else {
                    throw R117RuntimeError.uncoveredSource
                }
            }
        }

        func relativeFeatures(
            text: String, spans: [Range<Int>], contextTokenLimit: Int? = nil
        ) throws -> [[Float]] {
            let scalars = Array(text.unicodeScalars)
            let count = scalars.count
            var covered = Array(repeating: false, count: count)
            for offset in offsets {
                let lower = max(0, offset.lowerBound)
                let upper = min(count, offset.upperBound)
                if lower < upper {
                    for position in lower..<upper { covered[position] = true }
                }
            }
            let context: Document
            if let limit = contextTokenLimit {
                context = Document(
                    offsets: Array(offsets.prefix(limit)), vectors: Array(vectors.prefix(limit))
                )
            } else {
                context = self
            }
            let document = try context.pooled(in: 0..<count)
            return try spans.map { range in
                guard range.lowerBound >= 0, range.upperBound <= count, !range.isEmpty else {
                    throw R117RuntimeError.invalidCandidate
                }
                for position in range where !scalars[position].properties.isWhitespace {
                    if scalars[position].properties.generalCategory == .control { continue }
                    guard covered[position] else { throw R117RuntimeError.uncoveredSource }
                }
                return R117Encoder.relative(try pooled(in: range), context: document)
            }
        }
    }

    private let tokenizer: R117Tokenizer
    private let runner: R117HeadRunner

    init(tokenizer: R117Tokenizer, runner: R117HeadRunner) {
        self.tokenizer = tokenizer
        self.runner = runner
    }

    func document(text: String, function: String) throws -> Document {
        let encoding = try tokenizer.encode(text)
        guard !encoding.ids.isEmpty else { throw R117RuntimeError.uncoveredSource }
        let model = try runner.model(function: function)
        let empty = Array(repeating: Float(0), count: 384)
        var sums = Array(repeating: empty, count: encoding.ids.count)
        var counts = Array(repeating: 0, count: encoding.ids.count)
        for start in stride(from: 0, to: encoding.ids.count, by: 448) {
            try Task.checkCancellation()
            let end = min(start + 512, encoding.ids.count)
            let hidden = try predict(model: model, ids: Array(encoding.ids[start..<end]))
            for index in start..<end {
                for column in 0..<384 { sums[index][column] += hidden[index - start][column] }
                counts[index] += 1
            }
        }
        let vectors = sums.enumerated().map { index, row in
            row.map { Double($0) / Double(counts[index]) }
        }
        return Document(offsets: encoding.offsets, vectors: vectors)
    }

    func prepareDocuments(text: String) throws -> (
        original: R117DocumentEncoder.Prepared, teacher: R117DocumentEncoder.Prepared
    ) {
        try Task.checkCancellation()
        let encoding = try tokenizer.encode(text)
        guard !encoding.ids.isEmpty else { throw R117RuntimeError.uncoveredSource }
        try Task.checkCancellation()
        let original = try runner.model(function: "r117_original")
        try Task.checkCancellation()
        let teacher = try runner.model(function: "teacher_taskfit")
        try Task.checkCancellation()
        return (
            R117DocumentEncoder.Prepared(encoding: encoding, model: original),
            R117DocumentEncoder.Prepared(encoding: encoding, model: teacher)
        )
    }

    func prepareDocument(text: String, function: String) throws -> R117DocumentEncoder.Prepared {
        try Task.checkCancellation()
        let encoding = try tokenizer.encode(text)
        guard !encoding.ids.isEmpty else { throw R117RuntimeError.uncoveredSource }
        try Task.checkCancellation()
        let model = try runner.model(function: function)
        return R117DocumentEncoder.Prepared(encoding: encoding, model: model)
    }

    func documentConcurrently(
        text: String, function: String,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Document {
        let prepared = try prepareDocument(text: text, function: function)
        return try await prepared.document()
    }

    func last2(
        text: String, spans: [Range<Int>],
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> [[Float]] {
        let plan = try R117Last2Plan(text: text, spans: spans, tokenizer: tokenizer)
        let model = try runner.model(function: "teacher_last2")
        var results = Array(repeating: [Float](), count: spans.count)
        var completed = 0
        var nextProgress = 20
        for group in plan.groups {
            try Task.checkCancellation()
            try autoreleasepool {
                let input = try R117Tensor.input(ids: group.ids)
                let prediction = try model.prediction(from: input)
                let output = try R117Tensor.embeddings(from: prediction, length: group.ids.count)
                for selection in group.selections {
                    results[selection.candidate] = R117Tensor.pooled(
                        output, selected: selection.tokens
                    )
                }
            }
            completed += group.selections.count
            if completed >= nextProgress || completed == spans.count {
                progress?(completed, spans.count)
                nextProgress = completed + 20
            }
        }
        return results
    }

    func last2Concurrently(
        text: String, spans: [Range<Int>],
        isolation: isolated (any Actor)? = #isolation,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [[Float]] {
        let plan = try R117Last2Plan(text: text, spans: spans, tokenizer: tokenizer)
        let models = try runner.last2ModelPool(maximumModels: (plan.groups.count + 1) / 2)
        return try await R117ConcurrentEncoder.last2(
            plan: plan, models: models, candidateCount: spans.count, progress: progress
        )
    }

    func last2SharedConcurrently(
        text: String, spans: [Range<Int>],
        isolation: isolated (any Actor)? = #isolation,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [[Float]] {
        let prepared = try prepareShared(text: text)
        return try await prepared.last2(spans: spans, progress: progress)
    }

    func prepareShared(text: String) throws -> R117SharedContextEncoder.Prepared {
        try Task.checkCancellation()
        let source = Array(text.unicodeScalars)
        let normalized = source.map { scalar -> Unicode.Scalar in
            scalar.properties.generalCategory == .control
                && scalar != "\n" && scalar != "\r" && scalar != "\t" ? " " : scalar
        }
        let encoding = try tokenizer.encode(String(String.UnicodeScalarView(normalized)))
        try Task.checkCancellation()
        let model = try runner.model(function: "teacher_last2")
        return R117SharedContextEncoder.Prepared(encoding: encoding, source: source, model: model)
    }

    func predict(model: MLModel, ids: [Int]) throws -> [[Float]] {
        let prediction = try model.prediction(from: R117Tensor.input(ids: ids))
        let output = try R117Tensor.embeddings(from: prediction, length: ids.count)
        return R117Tensor.rows(output, count: ids.count)
    }

    static func relative(_ candidate: [Float], context: [Float]) -> [Float] {
        let product = zip(candidate, context).map(*)
        let dot = product.reduce(Float(0), +)
        let left = sqrt(candidate.map { $0 * $0 }.reduce(Float(0), +))
        let right = sqrt(context.map { $0 * $0 }.reduce(Float(0), +))
        return candidate + product + [dot / (left * right + 1e-8)]
    }
}

nonisolated extension R117Encoder {
    struct EncodedDocuments: Sendable {
        let original: Document
        let teacher: Document
    }

    struct Timed<Value: Sendable>: Sendable {
        let value: Value
        let duration: Double
    }

    static func runDocuments(
        original: R117DocumentEncoder.Prepared, teacher: R117DocumentEncoder.Prepared
    ) async throws -> Timed<EncodedDocuments> {
        let started = DispatchTime.now().uptimeNanoseconds
        async let originalDocument = original.document()
        async let teacherDocument = teacher.document()
        let (first, second) = try await (originalDocument, teacherDocument)
        try Task.checkCancellation()
        return Timed(
            value: EncodedDocuments(original: first, teacher: second),
            duration: Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        )
    }

    static func runShared(
        prepared: R117SharedContextEncoder.Prepared, ranges: [Range<Int>],
        progress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> Timed<[[Float]]> {
        let started = DispatchTime.now().uptimeNanoseconds
        let value = try await prepared.last2(spans: ranges, progress: progress)
        try Task.checkCancellation()
        return Timed(
            value: value,
            duration: Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        )
    }
}
