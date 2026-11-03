import Foundation

nonisolated struct R117ShortlistMention: Sendable {
    let start: Int
    let end: Int
    let surface: String
    let score: Double
}

/// 최초 표면의 표시 좌표와 최고점 mention의 특징 좌표를 각각 보존합니다.
nonisolated struct R117ShortlistGroup: Sendable {
    let key: String
    let text: String
    let bestScore: Double
    let rankScore: Double
    let mentions: [R117ShortlistMention]
    let distinctSpanCount: Int
    let positionHistogram: [Int]
    let nativeRank: Int?
    let guardedRank: Int?

    var featureMention: R117ShortlistMention? {
        mentions.reduce(nil) { best, mention in
            guard let best else { return mention }
            return mention.score > best.score ? mention : best
        }
    }

    func selectionCandidate(
        index: Int, source: String, frozenScore: Double
    ) throws -> R117SelectionCandidate {
        try selectionCandidate(index: index, sourceScalars: Array(source.unicodeScalars),
                               frozenScore: frozenScore)
    }

    func selectionCandidate(
        index: Int, sourceScalars: [UnicodeScalar], frozenScore: Double
    ) throws -> R117SelectionCandidate {
        let matching = mentions.filter {
            $0.surface.unicodeScalars.elementsEqual(text.unicodeScalars)
        }
        let chosen = matching.reduce(nil as R117ShortlistMention?) { best, mention in
            guard let best else { return mention }
            return mention.score > best.score ? mention : best
        }
        guard let start = chosen?.start ?? firstOccurrence(of: text, in: sourceScalars) else {
            throw R117SelectionError.invalidSpan
        }
        return R117SelectionCandidate(
            id: String(index), text: text, start: start, end: start + text.unicodeScalars.count,
            frozenScore: frozenScore, mentions: mentions.map { $0.start..<$0.end }
        )
    }

    private func firstOccurrence(of text: String, in scalars: [UnicodeScalar]) -> Int? {
        let needle = Array(text.unicodeScalars)
        guard !needle.isEmpty, needle.count <= scalars.count else { return nil }
        return (0...(scalars.count - needle.count)).first { start in
            scalars[start..<(start + needle.count)].elementsEqual(needle)
        }
    }
}
