import Foundation

nonisolated struct SpeechTermMatcher: Sendable {
    struct Result: Equatable {
        var text: String

        var score: Double
    }

    private struct Candidate: Sendable {
        let term: String
        let symbols: [Character]
    }

    private static let maxWindowTokens = 4
    private static let minFuzzySymbols = 7
    private static let fuzzyRatio = 0.2

    private static let particles: [String] = [
        "이랑", "에서", "으로", "에게", "까지", "부터", "하고", "처럼", "보다", "만큼",
        "을", "를", "이", "가", "은", "는", "의", "에", "로", "와", "과", "도", "만", "랑"
    ]

    private let exact: [String: String]
    private let candidates: [Candidate]

    init(replacements: [String: String]) {
        var exact: [String: String] = [:]
        var candidates: [Candidate] = []
        for (reading, term) in replacements.sorted(by: { $0.key < $1.key }) {
            let compact = reading.filter { !$0.isWhitespace }
            guard !compact.isEmpty else { continue }
            if exact[compact] == nil { exact[compact] = term }

            guard term.contains(where: { $0.isASCII && $0.isLetter }),
                  compact.allSatisfy(Self.isHangulSyllable) else { continue }
            let symbols = Self.symbols(of: compact)
            if symbols.count >= Self.minFuzzySymbols {
                candidates.append(Candidate(term: term, symbols: symbols))
            }
        }
        self.exact = exact
        self.candidates = candidates
    }

    var isEmpty: Bool { exact.isEmpty }

    mutating func bestCandidate<S: Sequence>(
        primary: String, alternatives: S
    ) -> String where S.Element == String {
        let primary = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isEmpty else { return primary }
        var best = primary
        var bestScore = restore(primary).score
        for alternative in alternatives {
            let text = alternative.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text != primary else { continue }
            let score = restore(text).score
            if score > bestScore + 0.5 {
                best = text
                bestScore = score
            }
        }
        return best
    }

    mutating func restore(_ text: String) -> Result {
        guard !exact.isEmpty else { return Result(text: text, score: 0) }
        if memo.count > 20_000 { memo.removeAll(keepingCapacity: true) }
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var output: [String] = []
        var score = 0.0
        var index = 0
        while index < tokens.count {
            if let match = bestMatch(in: tokens, at: index) {
                output.append(match.term + match.suffix)
                score += match.score
                index += match.tokenCount
            } else {
                output.append(tokens[index])
                index += 1
            }
        }
        return Result(text: output.joined(separator: " "), score: score)
    }

    private struct Match {
        let term: String
        let suffix: String
        let tokenCount: Int
        let score: Double
    }

    private struct StemMatch: Sendable {
        let term: String
        let score: Double
        let candidateSymbols: [Character]?
        let distance: Double
    }

    private var memo: [String: StemMatch?] = [:]

    private mutating func bestMatch(in tokens: [String], at start: Int) -> Match? {
        let limit = min(Self.maxWindowTokens, tokens.count - start)
        var best: Match?
        for count in 1...limit {
            let window = tokens[start..<(start + count)]

            guard window.dropLast().allSatisfy({ !$0.contains(where: Self.isPunctuation) }) else {
                break
            }
            let prefixLength = window.dropLast().reduce(0) { $0 + $1.count }
            let joined = window.joined()
            let (body, punctuation) = Self.splitTrailingPunctuation(joined)
            guard !body.isEmpty else { continue }
            for (stem, particle) in Self.stems(of: body) where stem.count > prefixLength {
                guard let found = memoizedMatch(stem: stem),
                      boundariesContribute(
                          to: found, stem: stem, firstCount: tokens[start].count,
                          prefixLength: prefixLength, tokenCount: count
                      ) else { continue }
                let candidate = Match(
                    term: found.term, suffix: particle + punctuation,
                    tokenCount: count, score: found.score
                )
                if best.map({ candidate.score > $0.score }) ?? true {
                    best = candidate
                }
            }
        }
        return best
    }

    private func boundariesContribute(
        to match: StemMatch, stem: String, firstCount: Int,
        prefixLength: Int, tokenCount: Int
    ) -> Bool {
        guard tokenCount > 1, let target = match.candidateSymbols else { return true }
        let withoutFirst = Self.symbols(of: String(stem.dropFirst(firstCount)))
        guard Self.distance(withoutFirst, target, limit: match.distance) > match.distance else {
            return false
        }
        let withoutLast = Self.symbols(of: String(stem.dropLast(stem.count - prefixLength)))
        return Self.distance(withoutLast, target, limit: match.distance) > match.distance
    }

    private mutating func memoizedMatch(stem: String) -> StemMatch? {
        if let cached = memo[stem] { return cached }
        let found = match(stem: stem)
        memo[stem] = .some(found)
        return found
    }

    private func match(stem: String) -> StemMatch? {
        if let term = exact[stem] {
            let count = max(Self.symbols(of: stem).count, stem.count)
            return StemMatch(
                term: term, score: Double(count) + 0.5,
                candidateSymbols: nil, distance: 0
            )
        }
        guard stem.allSatisfy(Self.isHangulSyllable) else { return nil }
        let symbols = Self.symbols(of: stem)
        guard symbols.count >= Self.minFuzzySymbols else { return nil }
        var best: StemMatch?
        for candidate in candidates {
            let allowed = Double(candidate.symbols.count) * Self.fuzzyRatio
            guard Double(abs(candidate.symbols.count - symbols.count)) * 0.5 <= allowed else {
                continue
            }
            let distance = Self.distance(symbols, candidate.symbols, limit: allowed)
            guard distance <= allowed else { continue }
            let score = Double(candidate.symbols.count) - distance * 2
            if best.map({ score > $0.score }) ?? true {
                best = StemMatch(
                    term: candidate.term, score: score,
                    candidateSymbols: candidate.symbols, distance: distance
                )
            }
        }
        return best
    }

    private static func stems(of body: String) -> [(stem: String, particle: String)] {
        var result: [(stem: String, particle: String)] = [(body, "")]
        for particle in particles where body.hasSuffix(particle) && body.count > particle.count {
            result.append((String(body.dropLast(particle.count)), particle))
        }
        return result
    }

    private static let onsets: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let vowels: [Character] = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")

    private static let codas: [Character?] = [
        nil, "ㄱ", "ㄲ", "ㄱ", "ㄴ", "ㄴ", "ㄴ", "ㄷ", "ㄹ", "ㄹ", "ㄹ", "ㄹ", "ㄹ", "ㄹ",
        "ㄹ", "ㄹ", "ㅁ", "ㅂ", "ㅂ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
    ]

    static func symbols(of text: String) -> [Character] {
        var result: [Character] = []
        for scalar in text.unicodeScalars {
            guard (0xAC00...0xD7A3).contains(scalar.value) else { continue }
            let index = Int(scalar.value) - 0xAC00
            let onset = index / 588
            if onset != 11 { result.append(onsets[onset]) }
            result.append(vowels[(index % 588) / 28])
            if let coda = codas[index % 28] { result.append(coda) }
        }
        return result
    }

    private static let confusableGroups: [Set<Character>] = [
        ["ㄱ", "ㄲ", "ㅋ"], ["ㄷ", "ㄸ", "ㅌ"], ["ㅂ", "ㅃ", "ㅍ"], ["ㅅ", "ㅆ"],
        ["ㅈ", "ㅉ", "ㅊ"], ["ㄴ", "ㄹ"], ["ㅐ", "ㅔ"], ["ㅒ", "ㅖ"], ["ㅙ", "ㅚ", "ㅞ"],
        ["ㅓ", "ㅗ"], ["ㅓ", "ㅡ"], ["ㅗ", "ㅜ", "ㅠ"], ["ㅜ", "ㅡ"], ["ㅕ", "ㅛ"]
    ]

    private static func areConfusable(_ lhs: Character, _ rhs: Character) -> Bool {
        confusableGroups.contains { $0.contains(lhs) && $0.contains(rhs) }
    }

    private static func substitutionCost(_ lhs: Character, _ rhs: Character) -> Double {
        if lhs == rhs { return 0 }
        return areConfusable(lhs, rhs) ? 0.5 : 1
    }

    private static func indelCost(_ symbol: Character) -> Double {
        symbol == "ㅡ" ? 0.5 : 1
    }

    static func distance(_ lhs: [Character], _ rhs: [Character], limit: Double) -> Double {
        var previous = [0.0]
        for symbol in rhs {
            previous.append(previous[previous.count - 1] + indelCost(symbol))
        }
        var current = previous
        for symbol in lhs {
            current[0] = previous[0] + indelCost(symbol)
            var rowMinimum = current[0]
            for (offset, other) in rhs.enumerated() {
                let column = offset + 1
                current[column] = min(
                    previous[offset] + substitutionCost(symbol, other),
                    previous[column] + indelCost(symbol),
                    current[offset] + indelCost(other)
                )
                rowMinimum = min(rowMinimum, current[column])
            }
            if rowMinimum > limit { return rowMinimum }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }

    private static func isHangulSyllable(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0xAC00...0xD7A3).contains($0.value) }
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        character.isPunctuation || character.isSymbol
    }

    private static func splitTrailingPunctuation(_ text: String) -> (String, String) {
        guard let last = text.lastIndex(where: { !isPunctuation($0) }) else { return ("", text) }
        let end = text.index(after: last)
        return (String(text[..<end]), String(text[end...]))
    }
}
