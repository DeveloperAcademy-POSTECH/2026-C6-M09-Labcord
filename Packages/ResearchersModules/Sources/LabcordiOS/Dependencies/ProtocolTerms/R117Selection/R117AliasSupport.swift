import Foundation

nonisolated enum R117AliasSupport {
    private static let acronymRegex = try? NSRegularExpression(pattern: "[A-Za-z]+")
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
        let words = (acronymRegex?.matches(
            in: long, range: NSRange(long.startIndex..., in: long)
        ) ?? []).compactMap { match -> String? in
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
