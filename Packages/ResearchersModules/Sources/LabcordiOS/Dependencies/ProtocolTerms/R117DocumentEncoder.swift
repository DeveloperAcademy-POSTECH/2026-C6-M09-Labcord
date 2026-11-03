import CoreML
import Foundation

/// 원래 window·누산 순서를 유지하며 한 모델의 async prediction을 최대 두 개 실행합니다.
nonisolated enum R117DocumentEncoder {
    typealias Prediction = @Sendable ([Int]) async throws -> [[Float]]

    struct Prepared: Sendable {
        private let encoding: R117Tokenizer.Encoding
        private let predictor: AsyncModel

        init(encoding: R117Tokenizer.Encoding, model: MLModel) {
            self.encoding = encoding
            predictor = AsyncModel(model: model)
        }

        func document() async throws -> R117Encoder.Document {
            try await R117DocumentEncoder.document(encoding: encoding) { ids in
                try await predictor.predict(ids: ids)
            }
        }
    }

    static func document(
        encoding: R117Tokenizer.Encoding, model: MLModel
    ) async throws -> R117Encoder.Document {
        try await Prepared(encoding: encoding, model: model).document()
    }

    static func document(
        encoding: R117Tokenizer.Encoding, prediction: @escaping Prediction
    ) async throws -> R117Encoder.Document {
        try Task.checkCancellation()
        guard encoding.ids.count == encoding.offsets.count else {
            throw R117RuntimeError.invalidTokenizer
        }
        guard !encoding.ids.isEmpty else { throw R117RuntimeError.uncoveredSource }
        let empty = Array(repeating: Float(0), count: 384)
        var sums = Array(repeating: empty, count: encoding.ids.count)
        var counts = Array(repeating: 0, count: encoding.ids.count)
        let starts = Array(stride(from: 0, to: encoding.ids.count, by: 448))
        for position in stride(from: 0, to: starts.count, by: 2) {
            try Task.checkCancellation()
            let end = min(position + 2, starts.count)
            let chunks = try await predict(
                starts: Array(starts[position..<end]), ids: encoding.ids,
                prediction: prediction
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
        let vectors = sums.enumerated().map { index, row in
            row.map { Double($0) / Double(counts[index]) }
        }
        return R117Encoder.Document(offsets: encoding.offsets, vectors: vectors)
    }
}

private extension R117DocumentEncoder {
    struct Chunk: Sendable {
        let start: Int
        let rows: [[Float]]
    }

    static func predict(
        starts: [Int], ids: [Int], prediction: @escaping Prediction
    ) async throws -> [Chunk] {
        try await withThrowingTaskGroup(of: Chunk.self) { tasks in
            for start in starts {
                let input = Array(ids[start..<min(start + 512, ids.count)])
                tasks.addTask {
                    try Task.checkCancellation()
                    let rows = try await prediction(input)
                    try Task.checkCancellation()
                    guard rows.count == input.count, rows.allSatisfy({ $0.count == 384 }) else {
                        throw R117RuntimeError.invalidModelOutput
                    }
                    return Chunk(start: start, rows: rows)
                }
            }
            var chunks: [Chunk] = []
            while let chunk = try await tasks.next() {
                try Task.checkCancellation()
                chunks.append(chunk)
            }
            return chunks.sorted { $0.start < $1.start }
        }
    }

    // 공유 모델은 Apple이 동시 호출을 지원하는 async API로만 사용합니다.
    // https://developer.apple.com/videos/play/wwdc2023/10049/
    // SDK가 MLModel의 Sendable 적합성을 제공하면 이 한정 wrapper를 제거합니다.
    final class AsyncModel: @unchecked Sendable {
        private let model: MLModel

        init(model: MLModel) {
            self.model = model
        }

        func predict(ids: [Int]) async throws -> [[Float]] {
            try Task.checkCancellation()
            let input = try R117Tensor.input(ids: ids)
            let prediction = try await model.prediction(
                from: input, options: MLPredictionOptions()
            )
            try Task.checkCancellation()
            let output = try R117Tensor.embeddings(from: prediction, length: ids.count)
            return R117Tensor.rows(output, count: ids.count)
        }
    }
}
