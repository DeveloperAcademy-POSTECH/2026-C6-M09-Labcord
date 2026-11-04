import Foundation

nonisolated public struct TermHint: Sendable {
    public let text: String
    public let start: Int
    public let end: Int
    public let score: Float
}

nonisolated enum NativeBIODecoder {
    static func decode(
        text: String, logits: [[Float]], offsets: [(Int, Int)]
    ) throws -> [TermHint] {
        let scalars = Array(text.unicodeScalars)
        guard logits.count == offsets.count else { throw R117NativeError.invalidPrediction }
        var boundary = 0
        for (start, end) in offsets {
            guard start == boundary, end > start, end <= scalars.count else {
                throw R117NativeError.invalidPrediction
            }
            boundary = end
        }
        guard boundary == scalars.count,
              logits.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) }) else {
            throw R117NativeError.invalidPrediction
        }
        let labels = try mostLikelyLabelSequence(logits)
        var spans: [TermHint] = []
        var spanStartIndex: Int?
        var accumulatedEntityProbability: Double = 0
        for index in 0...labels.count {
            if index % 256 == 0 { try Task.checkCancellation() }
            let label = index < labels.count ? labels[index] : 0
            if label != 2, let start = spanStartIndex {
                let lower = offsets[start].0
                let upper = offsets[index - 1].1
                spans.append(TermHint(
                    text: String(String.UnicodeScalarView(scalars[lower..<upper])),
                    start: lower, end: upper,
                    score: Float(accumulatedEntityProbability / Double(index - start))))
                spanStartIndex = nil
                accumulatedEntityProbability = 0
            }
            if label == 1 { spanStartIndex = index }
            if label != 0 {
                let row = logits[index].map(Double.init)
                let peak = row.max() ?? 0
                let weights = row.map { exp($0 - peak) }
                accumulatedEntityProbability += (weights[1] + weights[2]) / weights.reduce(0, +)
            }
        }

        let prioritizedSpans = try spans.map { span in
            try Task.checkCancellation()
            let concentration = ProtocolTermSourceCompletion.isExplicitConcentration(
                surface: span.text, range: span.start..<span.end, source: text)
            return (span: span, concentration: concentration)
        }.sorted {
            if $0.concentration != $1.concentration { return $0.concentration }
            return $0.span.score == $1.span.score
                ? $0.span.start < $1.span.start : $0.span.score > $1.span.score
        }
        return try select(prioritizedSpans.map(\.span))
    }

    static func select(_ spans: [TermHint]) throws -> [TermHint] {
        var seenSurfaceBytes = Set<Data>()
        var selected: [TermHint] = []
        for span in spans {
            try Task.checkCancellation()
            guard !isRepeatedHangul(span.text),
                  seenSurfaceBytes.insert(Data(span.text.utf8)).inserted else {
                continue
            }
            selected.append(span)
            if selected.count == 50 { break }
        }
        return selected
    }

    private static func isRepeatedHangul(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count >= 6,
              scalars.allSatisfy({ (0xAC00...0xD7A3).contains($0.value) }) else { return false }
        for width in 2...(scalars.count / 3) where scalars.count % width == 0 {
            if scalars.indices.allSatisfy({ scalars[$0] == scalars[$0 % width] }) { return true }
        }
        return false
    }

    private static func mostLikelyLabelSequence(_ logits: [[Float]]) throws -> [Int] {
        guard !logits.isEmpty else { return [] }
        var scores: [Double] = [0, -.infinity, -.infinity]
        var labelHistory: [[Int]] = []
        for (index, row) in logits.enumerated() {
            if index % 256 == 0 { try Task.checkCancellation() }
            var previousLabels = [0, 0, 0]
            var nextScores = [Double](repeating: -.infinity, count: 3)
            for label in 0..<3 {
                let allowedPreviousLabels = label == 2 ? [1, 2] : [0, 1, 2]
                var bestPreviousLabel = allowedPreviousLabels[0]
                for previous in allowedPreviousLabels
                where scores[previous] > scores[bestPreviousLabel] {
                    bestPreviousLabel = previous
                }
                previousLabels[label] = bestPreviousLabel
                nextScores[label] = scores[bestPreviousLabel] + Double(row[label])
            }
            let peak = nextScores.max() ?? 0
            scores = nextScores.map { $0 - peak }
            labelHistory.append(previousLabels)
        }
        var currentLabel = 0
        for label in 1..<3 where scores[label] > scores[currentLabel] { currentLabel = label }
        var labels = [Int](repeating: 0, count: logits.count)
        for index in labels.indices.reversed() {
            labels[index] = currentLabel
            currentLabel = labelHistory[index][currentLabel]
        }
        return labels
    }
}
