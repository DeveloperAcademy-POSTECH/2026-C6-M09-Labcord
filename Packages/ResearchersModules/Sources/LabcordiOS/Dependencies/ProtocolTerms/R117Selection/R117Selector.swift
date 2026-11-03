import Foundation

/// canonical 행 순서를 보존하며 alias support와 중첩 감점을 적용합니다.
nonisolated enum R117Selector {
    static func select(
        from candidates: [R117SelectionCandidate], source: String,
        scores: [Double], limit: Int = 50
    ) throws -> [Int] {
        try validate(candidates, source: source, scores: scores)
        let supported = R117AliasSupport.apply(to: scores, candidates: candidates, source: source)
        var active = Array(repeating: true, count: candidates.count)
        var penalties = Array(repeating: 0.0, count: candidates.count)
        var selected: [Int] = []
        while selected.count < min(limit, candidates.count) {
            try Task.checkCancellation()
            guard let index = bestIndex(scores: supported, active: active, penalties: penalties)
            else { break }
            selected.append(index)
            active[index] = false
            for other in candidates.indices where active[other] {
                let similarity = overlap(candidates[other], candidates[index])
                penalties[other] = max(penalties[other], similarity)
            }
        }
        return selected
    }

    private static func validate(
        _ candidates: [R117SelectionCandidate], source: String, scores: [Double]
    ) throws {
        guard scores.count == candidates.count else { throw R117SelectionError.misalignedScores }
        guard scores.allSatisfy(\.isFinite),
              candidates.allSatisfy({ $0.frozenScore.isFinite })
        else { throw R117SelectionError.nonfiniteScore }
        let scalars = Array(source.unicodeScalars)
        let scalarCount = scalars.count
        guard candidates.allSatisfy({ candidate in
            candidate.start >= 0 && candidate.end > candidate.start && candidate.end <= scalarCount
                && scalars[candidate.start..<candidate.end]
                    .elementsEqual(candidate.text.unicodeScalars)
                && candidate.mentions.allSatisfy {
                    $0.lowerBound >= 0 && $0.upperBound > $0.lowerBound
                        && $0.upperBound <= scalarCount
                }
        }) else { throw R117SelectionError.invalidSpan }
    }

    private static func bestIndex(
        scores: [Double], active: [Bool], penalties: [Double]
    ) -> Int? {
        var best: Int?
        var bestScore = -Double.infinity
        for index in scores.indices where active[index] {
            let adjusted = scores[index] - 0.25 * penalties[index]
            // Strict comparison preserves NumPy argmax's first canonical-row tie break.
            if adjusted > bestScore {
                best = index
                bestScore = adjusted
            }
        }
        return best
    }

    private static func overlap(
        _ candidate: R117SelectionCandidate, _ selected: R117SelectionCandidate
    ) -> Double {
        let length = candidate.end - candidate.start
        let selectedLength = selected.end - selected.start
        let left = max(candidate.start, selected.start)
        let right = min(candidate.end, selected.end)
        let intersection = max(0, right - left)
        let ratio = Double(intersection) / Double(min(length, selectedLength))
        let sizeRatio = Double(min(length, selectedLength)) / Double(max(length, selectedLength))
        return ratio >= 0.8 && sizeRatio >= 0.5 ? ratio : 0
    }
}
