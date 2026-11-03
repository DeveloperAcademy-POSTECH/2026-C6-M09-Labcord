import CoreML
import Foundation

/// 후보별 ±160 문맥 대신 문서 window를 공유합니다. 기존 후보별 특징과 점수는 달라집니다.
nonisolated enum R117SharedContextEncoder {
    typealias Prediction = @Sendable ([Int]) async throws -> [[Float]]

    struct Prepared: Sendable {
        private let encoding: R117Tokenizer.Encoding
        private let source: [Unicode.Scalar]
        private let predictor: AsyncModel

        init(encoding: R117Tokenizer.Encoding, source: [Unicode.Scalar], model: MLModel) {
            self.encoding = encoding
            self.source = source
            predictor = AsyncModel(model: model)
        }

        func last2(
            spans: [Range<Int>], progress: (@Sendable (Int, Int) -> Void)? = nil
        ) async throws -> [[Float]] {
            try await R117SharedContextEncoder.last2(
                encoding: encoding, source: source, spans: spans, progress: progress
            ) { ids in
                try await predictor.predict(ids)
            }
        }
    }

    static func last2(
        encoding: R117Tokenizer.Encoding, source: [Unicode.Scalar], spans: [Range<Int>],
        model: MLModel, progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [[Float]] {
        try await Prepared(encoding: encoding, source: source, model: model)
            .last2(spans: spans, progress: progress)
    }

    static func last2(
        encoding: R117Tokenizer.Encoding, source: [Unicode.Scalar], spans: [Range<Int>],
        progress: (@Sendable (Int, Int) -> Void)? = nil,
        prediction: @escaping Prediction
    ) async throws -> [[Float]] {
        try Task.checkCancellation()
        let selections = try selections(encoding: encoding, source: source, spans: spans)
        guard !selections.isEmpty else { return [] }
        let vectors = try await document(ids: encoding.ids, prediction: prediction)
        return try selections.enumerated().map { number, selected in
            try Task.checkCancellation()
            var pooled = Array(repeating: Float(0), count: 384)
            for token in selected {
                for column in 0..<384 { pooled[column] += vectors[token][column] }
            }
            let row = pooled.map { $0 / Float(selected.count) }
            guard row.allSatisfy(\.isFinite) else { throw R117RuntimeError.invalidModelOutput }
            let completed = number + 1
            if completed.isMultiple(of: 20) || completed == selections.count {
                try Task.checkCancellation()
                progress?(completed, selections.count)
            }
            try Task.checkCancellation()
            return row
        }
    }
}

nonisolated private extension R117SharedContextEncoder {
    struct Chunk: Sendable {
        let start: Int
        let rows: [[Float]]
    }

    static func document(ids: [Int], prediction: @escaping Prediction) async throws -> [[Float]] {
        let empty = Array(repeating: Float(0), count: 384)
        var sums = Array(repeating: empty, count: ids.count)
        var counts = Array(repeating: 0, count: ids.count)
        let starts = Array(stride(from: 0, to: ids.count, by: 448))
        for position in stride(from: 0, to: starts.count, by: 2) {
            try Task.checkCancellation()
            let end = min(position + 2, starts.count)
            let chunks = try await predict(
                starts: Array(starts[position..<end]), ids: ids, prediction: prediction
            )
            for chunk in chunks {
                try Task.checkCancellation()
                for (row, vector) in chunk.rows.enumerated() {
                    let index = chunk.start + row
                    for column in 0..<384 { sums[index][column] += vector[column] }
                    counts[index] += 1
                }
            }
        }
        try Task.checkCancellation()
        // prototype처럼 overlap을 Float32로 평균한 뒤 후보 토큰도 같은 가중치로 평균합니다.
        return try sums.enumerated().map { index, row in
            try Task.checkCancellation()
            guard counts[index] > 0 else { throw R117RuntimeError.uncoveredSource }
            let averaged = row.map { $0 / Float(counts[index]) }
            guard averaged.allSatisfy(\.isFinite) else {
                throw R117RuntimeError.invalidModelOutput
            }
            return averaged
        }
    }

    static func predict(
        starts: [Int], ids: [Int], prediction: @escaping Prediction
    ) async throws -> [Chunk] {
        try await withThrowingTaskGroup(of: Chunk.self) { tasks in
            for start in starts {
                let end = min(start + 510, ids.count)
                let input = [0] + ids[start..<end] + [2]
                tasks.addTask {
                    try Task.checkCancellation()
                    let rows = try await prediction(input)
                    try Task.checkCancellation()
                    guard rows.count == input.count, rows.allSatisfy({
                        $0.count == 384 && $0.allSatisfy(\.isFinite)
                    }) else { throw R117RuntimeError.invalidModelOutput }
                    return Chunk(start: start, rows: Array(rows.dropFirst().dropLast()))
                }
            }
            var chunks: [Chunk] = []
            while let chunk = try await tasks.next() {
                try Task.checkCancellation()
                chunks.append(chunk)
            }
            // 완료 순서가 달라도 기존 window 순서로 Float32를 누산합니다.
            return chunks.sorted { $0.start < $1.start }
        }
    }

    static func selections(
        encoding: R117Tokenizer.Encoding, source: [Unicode.Scalar], spans: [Range<Int>]
    ) throws -> [[Int]] {
        guard encoding.ids.count == encoding.offsets.count,
              encoding.offsets.allSatisfy({ $0.lowerBound >= 0
                && $0.upperBound <= source.count }) else {
            throw R117RuntimeError.invalidTokenizer
        }
        guard !encoding.ids.isEmpty else { throw R117RuntimeError.uncoveredSource }
        var covered = Array(repeating: false, count: source.count)
        for offset in encoding.offsets {
            try Task.checkCancellation()
            for position in offset { covered[position] = true }
        }
        let pairs = zip(encoding.offsets, encoding.offsets.dropFirst())
        let ordered = pairs.allSatisfy { left, right in
            left.lowerBound <= right.lowerBound && left.upperBound <= right.upperBound
        }
        return try spans.map { range in
            try Task.checkCancellation()
            guard range.lowerBound >= 0, range.upperBound <= source.count, !range.isEmpty else {
                throw R117RuntimeError.invalidCandidate
            }
            for position in range where !source[position].properties.isWhitespace {
                if source[position].properties.generalCategory == .control { continue }
                guard covered[position] else { throw R117RuntimeError.uncoveredSource }
            }
            let indices: Range<Int>
            if ordered {
                let lower = firstOffset(encoding.offsets) { $0.upperBound > range.lowerBound }
                let upper = firstOffset(encoding.offsets) { $0.lowerBound >= range.upperBound }
                indices = lower..<upper
            } else {
                indices = encoding.offsets.indices
            }
            let selected = indices.filter { encoding.offsets[$0].overlaps(range) }
            guard !selected.isEmpty else { throw R117RuntimeError.uncoveredSource }
            return selected
        }
    }

    static func firstOffset(
        _ offsets: [Range<Int>], where predicate: (Range<Int>) -> Bool
    ) -> Int {
        var lower = 0
        var upper = offsets.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if predicate(offsets[middle]) { upper = middle } else { lower = middle + 1 }
        }
        return lower
    }

    // MLModel의 공유는 공식 async prediction에 한정합니다. 동기 호출과 섞지 않습니다.
    // https://developer.apple.com/videos/play/wwdc2023/10049/
    // SDK가 MLModel에 Sendable을 제공하면 이 한정 wrapper를 제거합니다.
    final class AsyncModel: @unchecked Sendable {
        private let model: MLModel

        init(model: MLModel) {
            self.model = model
        }

        func predict(_ ids: [Int]) async throws -> [[Float]] {
            try Task.checkCancellation()
            let input = try R117Tensor.input(ids: ids)
            let result = try await model.prediction(from: input, options: MLPredictionOptions())
            try Task.checkCancellation()
            let output = try R117Tensor.embeddings(from: result, length: ids.count)
            return R117Tensor.rows(output, count: ids.count)
        }
    }
}
