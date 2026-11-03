import Foundation

/// shortlist v2.1의 고정 grouping과 순위 규칙을 적용합니다.
nonisolated enum R117ShortlistBuilder {
    static func build(
        source: String, pool: R117NativeCandidatePool
    ) throws -> [R117ShortlistGroup] {
        let scalars = Array(source.unicodeScalars)
        var groups: [String: Accumulator] = [:]
        var order: [String] = []
        for raw in pool.rawCandidates where raw.retained {
            try Task.checkCancellation()
            guard raw.start >= 0, raw.end > raw.start, raw.end <= scalars.count,
                  raw.score.isFinite else { throw R117SelectionError.invalidSpan }
            let surface = String(String.UnicodeScalarView(scalars[raw.start..<raw.end]))
            let key = R117SelectionNormalization.key(surface)
            guard !key.isEmpty else { continue }
            if groups[key] == nil {
                groups[key] = Accumulator(key: key, text: surface)
                order.append(key)
            }
            groups[key]?.append(raw, surface: surface)
        }
        let native = ranks(pool.nativeOrder)
        let guarded = ranks(pool.guardedOrder)
        let length = max(1, scalars.count)
        let result = order.compactMap { key in
            groups[key]?.group(length: length, native: native[key], guarded: guarded[key])
        }.sorted(by: orderedBefore)
        return Array(result.prefix(2_000))
    }

    private static func ranks(_ terms: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for (index, term) in terms.enumerated() {
            let key = R117SelectionNormalization.key(term)
            if !key.isEmpty && result[key] == nil { result[key] = index + 1 }
        }
        return result
    }

    private static func orderedBefore(
        _ left: R117ShortlistGroup, _ right: R117ShortlistGroup
    ) -> Bool {
        let leftTier = tier(left)
        let rightTier = tier(right)
        if leftTier != rightTier { return leftTier < rightTier }
        let leftRank = left.guardedRank ?? left.nativeRank ?? 1_000_000_000
        let rightRank = right.guardedRank ?? right.nativeRank ?? 1_000_000_000
        if leftRank != rightRank { return leftRank < rightRank }
        if left.rankScore != right.rankScore { return left.rankScore > right.rankScore }
        if left.bestScore != right.bestScore { return left.bestScore > right.bestScore }
        return left.key.unicodeScalars.lexicographicallyPrecedes(right.key.unicodeScalars)
    }

    private static func tier(_ group: R117ShortlistGroup) -> Int {
        if group.guardedRank != nil { return 0 }
        return group.nativeRank != nil ? 1 : 2
    }

    private struct Accumulator {
        let key: String
        let text: String
        var bestScore = -Double.infinity
        var spans: [Range<Int>: R117ShortlistMention] = [:]

        mutating func append(_ raw: R117NativeRawCandidate, surface: String) {
            bestScore = max(bestScore, raw.score)
            let span = raw.start..<raw.end
            guard spans[span].map({ raw.score > $0.score }) ?? true else { return }
            spans[span] = R117ShortlistMention(
                start: raw.start, end: raw.end, surface: surface, score: raw.score
            )
        }

        func group(length: Int, native: Int?, guarded: Int?) -> R117ShortlistGroup {
            let mentions = spans.values.sorted {
                $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start
            }
            var histogram = Array(repeating: 0, count: 8)
            for mention in mentions {
                histogram[min(7, mention.start * 8 / length)] += 1
            }
            let occupied = histogram.filter { $0 > 0 }.count
            let score = bestScore + 0.10 * log1p(Double(mentions.count))
                + 0.03 * log1p(Double(occupied)) + 0.12 * min(1, Double(occupied) / 4)
                + R117ShortlistShape.score(text)
            return R117ShortlistGroup(
                key: key, text: text, bestScore: bestScore, rankScore: score,
                mentions: Array(mentions.prefix(8)), distinctSpanCount: mentions.count,
                positionHistogram: histogram, nativeRank: native, guardedRank: guarded
            )
        }
    }
}

nonisolated private enum R117ShortlistShape {
    static func score(_ surface: String) -> Double {
        let trimmed = R117SelectionNormalization.trim(surface)
        guard !trimmed.isEmpty else { return -10 }
        let scalars = trimmed.unicodeScalars
        let digit = scalars.contains {
            $0.properties.numericType == .decimal || $0.properties.numericType == .digit
        }
        let normalizedLength = R117SelectionNormalization.key(trimmed).unicodeScalars.count
        var result = 0.08 * log1p(Double(normalizedLength))
        if digit { result += 0.12 }
        if scalars.contains(where: { $0.properties.isUppercase }) { result += 0.08 }
        if scalars.contains(where: { "-/+()[]%".unicodeScalars.contains($0) }) { result += 0.06 }
        if scalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }) { result += 0.05 }
        if scalars.count == 1 { result -= 0.12 }
        return result
    }
}
