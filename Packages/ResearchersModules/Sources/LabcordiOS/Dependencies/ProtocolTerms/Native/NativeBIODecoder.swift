import Foundation

nonisolated public struct TermHint: Sendable {
    public let text: String
    public let start: Int
    public let end: Int
    public let score: Float
}

/// O=0, B=1, I=2. I는 B/I 뒤에서만 허용하며 별도의 사전·확장 규칙은 없습니다.
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
        let labels = try path(logits)
        var spans: [TermHint] = []
        var first: Int?
        var probability: Double = 0
        for index in 0...labels.count {
            if index % 256 == 0 { try Task.checkCancellation() }
            let label = index < labels.count ? labels[index] : 0
            if label != 2, let start = first {
                let lower = offsets[start].0
                let upper = offsets[index - 1].1
                spans.append(TermHint(
                    text: String(String.UnicodeScalarView(scalars[lower..<upper])),
                    start: lower, end: upper, score: Float(probability / Double(index - start))))
                first = nil
                probability = 0
            }
            if label == 1 { first = index }
            if label != 0 {
                let row = logits[index].map(Double.init)
                let peak = row.max() ?? 0
                let weights = row.map { exp($0 - peak) }
                probability += (weights[1] + weights[2]) / weights.reduce(0, +)
            }
        }
        // 원문에 명시된 농도 완전형을 먼저 보존하고, 그룹 안에서는 모델 순서를 유지합니다.
        let prioritized = try spans.map { span in
            try Task.checkCancellation()
            let concentration = ProtocolTermSourceCompletion.isExplicitConcentration(
                surface: span.text, range: span.start..<span.end, source: text)
            return (span: span, concentration: concentration)
        }.sorted {
            if $0.concentration != $1.concentration { return $0.concentration }
            return $0.span.score == $1.span.score
                ? $0.span.start < $1.span.start : $0.span.score > $1.span.score
        }
        return try select(prioritized.map(\.span))
    }

    static func select(_ spans: [TermHint]) throws -> [TermHint] {
        var seen = Set<Data>()
        var selected: [TermHint] = []
        for span in spans {
            try Task.checkCancellation()
            guard !isRepeatedHangul(span.text), seen.insert(Data(span.text.utf8)).inserted else {
                continue
            }
            selected.append(span)
            if selected.count == 50 { break }
        }
        return selected
    }

    // 화학식·숫자·단위를 건드리지 않고 Hangul-only 전체 표면의 반복만 제외합니다.
    private static func isRepeatedHangul(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count >= 6,
              scalars.allSatisfy({ (0xAC00...0xD7A3).contains($0.value) }) else { return false }
        for width in 2...(scalars.count / 3) where scalars.count % width == 0 {
            if scalars.indices.allSatisfy({ scalars[$0] == scalars[$0 % width] }) { return true }
        }
        return false
    }

    private static func path(_ logits: [[Float]]) throws -> [Int] {
        guard !logits.isEmpty else { return [] }
        var scores: [Double] = [0, -.infinity, -.infinity]
        var history: [[Int]] = []
        for (index, row) in logits.enumerated() {
            if index % 256 == 0 { try Task.checkCancellation() }
            var parents = [0, 0, 0]
            var next = [Double](repeating: -.infinity, count: 3)
            for label in 0..<3 {
                let allowed = label == 2 ? [1, 2] : [0, 1, 2]
                var best = allowed[0]
                for previous in allowed where scores[previous] > scores[best] { best = previous }
                parents[label] = best
                next[label] = scores[best] + Double(row[label])
            }
            let peak = next.max() ?? 0
            scores = next.map { $0 - peak }
            history.append(parents)
        }
        var current = 0
        for label in 1..<3 where scores[label] > scores[current] { current = label }
        var labels = [Int](repeating: 0, count: logits.count)
        for index in labels.indices.reversed() {
            labels[index] = current
            current = history[index][current]
        }
        return labels
    }
}
