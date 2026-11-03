import Foundation
@testable import LabcordiOS
import XCTest

final class R117SelectionOptimizationTests: XCTestCase {
    func testSharedScalarsMatchOriginalCandidatePath() throws {
        let source = "🧪 e\u{301} NaCl 5 mg/mL (PBS) NaCl"
        for text in ["e\u{301}", "NaCl", "5 mg/mL", "PBS", "missing"] {
            let group = R117ShortlistGroup(
                key: text, text: text, bestScore: 1, rankScore: 1, mentions: [],
                distinctSpanCount: 0, positionHistogram: [], nativeRank: nil, guardedRank: nil
            )
            let baseline = BaselineR117ShortlistGroup(
                key: text, text: text, bestScore: 1, rankScore: 1, mentions: [],
                distinctSpanCount: 0, positionHistogram: [], nativeRank: nil, guardedRank: nil
            )
            let original = Result { try baseline.selectionCandidate(index: 0,
                source: source,
                frozenScore: 1) }
            let shared = Result {
                try group.selectionCandidate(index: 0,
                    sourceScalars: Array(source.unicodeScalars),
                    frozenScore: 1)
            }
            switch (original, shared) {
            case let (.success(left), .success(right)): XCTAssertEqual(left, right)
            case let (.failure(left), .failure(right)):
                XCTAssertEqual(left as? R117SelectionError, .invalidSpan)
                XCTAssertEqual(right as? R117SelectionError, .invalidSpan)
            default: XCTFail("Candidate paths differ for \(text)")
            }
        }
    }

    func testSelectionMatchesBaselineOverlapLoop() throws {
        let source = "abcdefghij 5 mg/mL"
        let spans = [0..<10, 0..<9, 11..<18, 11..<15]
        let scalars = Array(source.unicodeScalars)
        let candidates = spans.enumerated().map { index, span in
            R117SelectionCandidate(id: String(index),
                text: String(String.UnicodeScalarView(scalars[span])),
                                   start: span.lowerBound, end: span.upperBound,
                                   frozenScore: 0, mentions: [span])
        }
        for scores in [[1.0, 0.95, 0.8, 0.8], [1, 1, 1, 1]] {
            let baseline = try BaselineR117Selector.select(from: candidates,
                source: source,
                scores: scores)
            XCTAssertEqual(try R117Selector.select(from: candidates,
                source: source,
                scores: scores),
                baseline)
        }
    }
    func testAliasApplyMatchesOriginalRegexImplementation() {
        for source in ["phosphate buffered saline (PBS)", "인산 (H3PO4)",
                       "sodium chloride (NaCl2)", "alpha beta (AB2)",
                       "e\u{301} phosphate buffered saline （PBS）",
                           "phosphate buffered saline (PBS) PBS"] {
            let texts = ["phosphate buffered saline",
                "PBS",
                "인산",
                "H3PO4",
                "sodium chloride",
                "NaCl2",
                "alpha beta",
                "AB2"]
            let scalars = Array(source.unicodeScalars)
            let candidates = texts.compactMap { text -> R117SelectionCandidate? in
                let needle = Array(text.unicodeScalars)
                guard needle.count <= scalars.count,
                      let start = (0...(scalars.count - needle.count)).first(where: {
                          scalars[$0..<($0 + needle.count)].elementsEqual(needle)
                      }) else { return nil }
                return R117SelectionCandidate(id: text,
                    text: text,
                    start: start,
                    end: start + needle.count,
                                              frozenScore: 0.1,
                                                  mentions: [start..<(start + needle.count)])
            }
            let scores = candidates.indices.map { Double($0) / 10 }
            XCTAssertEqual(R117AliasSupport.apply(to: scores,
                candidates: candidates,
                source: source),
                           BaselineR117AliasSupport.apply(to: scores,
                               candidates: candidates,
                               source: source))
        }
    }

    func testRepresentativeMentionsAndFallbackMatchBaseline() throws {
        let source = "85% 인산 염산 0.0100 M mg/mL 인산"
        let scalars = Array(source.unicodeScalars)
        XCTAssertEqual(String(String.UnicodeScalarView(scalars[25..<27])), "인산")
        for text in ["85%", "인산", "염산", "0.0100 M", "mg/mL", "missing"] {
            let mentions = [R117ShortlistMention(start: 4, end: 6, surface: "인산", score: 1),
                            R117ShortlistMention(start: 25, end: 27, surface: "인산", score: 2)]
            let oldMentions = mentions.map { BaselineR117ShortlistMention(start: $0.start,
                end: $0.end,
                surface: $0.surface,
                score: $0.score) }
            let group = R117ShortlistGroup(key: text,
                text: text,
                bestScore: 1,
                rankScore: 1,
                mentions: mentions,
                                          distinctSpanCount: 2,
                                              positionHistogram: [],
                                              nativeRank: nil,
                                              guardedRank: nil)
            let baseline = BaselineR117ShortlistGroup(key: text,
                text: text,
                bestScore: 1,
                rankScore: 1,
                mentions: oldMentions,
                    distinctSpanCount: 2,
                    positionHistogram: [],
                    nativeRank: nil,
                    guardedRank: nil)
            let actual = Result { try group.selectionCandidate(index: 0,
                source: source,
                frozenScore: 1) }
            let expected = Result { try baseline.selectionCandidate(index: 0,
                source: source,
                frozenScore: 1) }
            switch (actual, expected) {
            case let (.success(actual), .success(expected)):
                XCTAssertEqual(actual, expected)
                if text == "인산" {
                    XCTAssertEqual(actual.start, 25)
                    XCTAssertEqual(actual.end, 27)
                }
            case let (.failure(actual), .failure(expected)):
                XCTAssertEqual(actual as? R117SelectionError, .invalidSpan)
                XCTAssertEqual(expected as? R117SelectionError, .invalidSpan)
            default: XCTFail("Candidate paths differ for \(text)")
            }
        }
    }

}

// d7bc5d2 원본: 최적화 전 동작과 독립적으로 비교하기 위한 기준 구현입니다.

nonisolated struct BaselineR117ShortlistMention: Sendable {
    let start: Int
    let end: Int
    let surface: String
    let score: Double
}
/// 최초 표면의 표시 좌표와 최고점 mention의 특징 좌표를 각각 보존합니다.
nonisolated struct BaselineR117ShortlistGroup: Sendable {
    let key: String
    let text: String
    let bestScore: Double
    let rankScore: Double
    let mentions: [BaselineR117ShortlistMention]
    let distinctSpanCount: Int
    let positionHistogram: [Int]
    let nativeRank: Int?
    let guardedRank: Int?
    var featureMention: BaselineR117ShortlistMention? {
        mentions.reduce(nil) { best, mention in
            guard let best else { return mention }
            return mention.score > best.score ? mention : best
        }
    }
    func selectionCandidate(
        index: Int, source: String, frozenScore: Double
    ) throws -> R117SelectionCandidate {
        let matching = mentions.filter {
            $0.surface.unicodeScalars.elementsEqual(text.unicodeScalars)
        }
        let chosen = matching.reduce(nil as BaselineR117ShortlistMention?) { best, mention in
            guard let best else { return mention }
            return mention.score > best.score ? mention : best
        }
        let scalars = Array(source.unicodeScalars)
        guard let start = chosen?.start ?? firstOccurrence(of: text, in: scalars) else {
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
// d7bc5d2 원본: 최적화 전 동작과 독립적으로 비교하기 위한 기준 구현입니다.
nonisolated enum BaselineR117AliasSupport {
    private static let functionWords: Set<String> = [
        "of", "the", "and", "for", "in", "on", "with", "a", "an", "to"
    ]
    static func apply(
        to scores: [Double], candidates: [R117SelectionCandidate], source: String
    ) -> [Double] {
        let pairs = links(candidates: candidates, source: source)
        var supported = scores
        for (left, right) in pairs {
            // Use the original vector on both sides; alias support is not transitive.
            supported[left] = max(supported[left], scores[right])
            supported[right] = max(supported[right], scores[left])
        }
        return supported
    }
    private static func links(
        candidates: [R117SelectionCandidate], source: String
    ) -> [(Int, Int)] {
        var byKey: [String: Int] = [:]
        var mentions: [Int: [Int]] = [:]
        for (index, candidate) in candidates.enumerated() {
            // The reference dictionary keeps the last row for duplicate normalized text.
            byKey[R117SelectionNormalization.key(candidate.text)] = index
            for mention in candidate.mentions {
                mentions[mention.upperBound, default: []].append(index)
            }
        }
        let sourceScalars = Array(source.unicodeScalars)
        let matches = matches("[（(]([^()（）\\r\\n]{2,100})[)）]", in: source)
        var pairs = Set<AliasPair>()
        for match in matches {
            guard let innerRange = Range(match.range(at: 1), in: source),
                  let wholeRange = Range(match.range, in: source),
                  let scalarIndex = wholeRange.lowerBound.samePosition(in: source.unicodeScalars)
            else { continue }
            let inside = trimWhitespace(String(source[innerRange]))
            guard let right = byKey[R117SelectionNormalization.key(inside)] else { continue }
            let start = source.unicodeScalars.distance(from: source.unicodeScalars.startIndex,
                                                      to: scalarIndex)
            let end = precedingEnd(start: start, scalars: sourceScalars)
            guard let left = precedingCandidate(
                indices: mentions[end, default: []], excluding: right,
                inside: inside, candidates: candidates
            ) else { continue }
            pairs.insert(AliasPair(left: min(left, right), right: max(left, right)))
        }
        return pairs.sorted {
            $0.left == $1.left ? $0.right < $1.right : $0.left < $1.left
        }.map { ($0.left, $0.right) }
    }
    private static func precedingEnd(start: Int, scalars: [UnicodeScalar]) -> Int {
        var end = start
        while end > 0 && start - end < 8
                && R117SelectionNormalization.isWhitespace(scalars[end - 1]) {
            end -= 1
        }
        return end
    }
    private static func precedingCandidate(
        indices: [Int], excluding right: Int, inside: String,
        candidates: [R117SelectionCandidate]
    ) -> Int? {
        var best: Int?
        for index in R117IntegerSetOrder.values(indices) where index != right {
            let candidate = candidates[index]
            guard isAlias(inside: inside, outside: candidate.text) else { continue }
            if let previous = best {
                let old = candidates[previous]
                let higherScore = candidate.frozenScore > old.frozenScore
                let shorter = candidate.frozenScore == old.frozenScore
                    && candidate.text.unicodeScalars.count < old.text.unicodeScalars.count
                if higherScore || shorter { best = index }
            } else {
                best = index
            }
        }
        return best
    }
    private static func isAlias(inside: String, outside: String) -> Bool {
        if acronymMatches(short: inside, long: outside)
            || acronymMatches(short: outside, long: inside) { return true }
        let bilingual = contains("[가-힣]", in: outside)
            && contains("^[A-Za-z][A-Za-z /\\-]{1,90}$", in: inside)
        let chemical = contains("^(?:[A-Z][a-z]?\\d*){1,10}$", in: inside)
            && contains("\\d", in: inside) && contains("[A-Za-z가-힣]", in: outside)
            && !contains("\\d", in: outside)
        return bilingual || chemical
    }
    private static func acronymMatches(short: String, long: String) -> Bool {
        let letters = short.filter { $0.isASCII && $0.isLetter }
        let uppercase = short.filter { $0.isASCII && $0.isUppercase }.count
        guard (2...10).contains(letters.count), uppercase >= 2,
              !contains("[^A-Za-z0-9\\- ]", in: short), !contains("\\d", in: short),
              long.unicodeScalars.count > short.unicodeScalars.count else { return false }
        let words = matches("[A-Za-z]+", in: long).compactMap { match -> String? in
            guard let range = Range(match.range, in: long) else { return nil }
            return String(long[range])
        }
        guard words.count >= 2 else { return false }
        let initials = words.compactMap(\.first).map(String.init).joined().lowercased()
        let filtered = words.filter { !functionWords.contains($0.lowercased()) }
            .compactMap(\.first).map(String.init).joined().lowercased()
        return letters.lowercased() == initials || letters.lowercased() == filtered
    }
    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }
    private static func contains(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
    private static func trimWhitespace(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        let trimmed = scalars.drop(while: R117SelectionNormalization.isWhitespace)
            .reversed().drop(while: R117SelectionNormalization.isWhitespace).reversed()
        return String(String.UnicodeScalarView(trimmed))
    }
    private struct AliasPair: Hashable {
        let left: Int
        let right: Int
    }
}
// d7bc5d2 원본: 최적화 전 동작과 독립적으로 비교하기 위한 기준 구현입니다.
/// canonical 행 순서를 보존하며 alias support와 중첩 감점을 적용합니다.
nonisolated enum BaselineR117Selector {
    static func select(
        from candidates: [R117SelectionCandidate], source: String,
        scores: [Double], limit: Int = 50
    ) throws -> [Int] {
        try validate(candidates, source: source, scores: scores)
        let supported = BaselineR117AliasSupport.apply(to: scores,
            candidates: candidates,
            source: source)
        var active = Array(repeating: true, count: candidates.count)
        var penalties = Array(repeating: 0.0, count: candidates.count)
        var selected: [Int] = []
        while selected.count < min(limit, candidates.count) {
            try Task.checkCancellation()
            guard let index = bestIndex(scores: supported, active: active, penalties: penalties)
            else { break }
            selected.append(index)
            active[index] = false
            for other in candidates.indices {
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
