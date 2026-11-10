import Foundation

nonisolated public struct SpeechSessionVocabulary: Equatable, Sendable {

    public var contextualStrings: [String]

    public var replacements: [String: String]

    public init(contextualStrings: [String] = [], replacements: [String: String] = [:]) {
        self.contextualStrings = contextualStrings
        self.replacements = replacements
    }

    public static func terms(from raw: [String]) -> [String] {
        SpeechVocabulary.terms(from: raw)
    }

    public static func usingCachedReadings(for terms: [String]) -> SpeechSessionVocabulary {
        SpeechSessionVocabulary(
            contextualStrings: SpeechVocabulary.contextualStrings(
                for: terms, modelReading: SpeechPhoneticTranslator.cachedReading
            ),
            replacements: SpeechVocabulary.replacements(
                for: terms, modelReading: SpeechPhoneticTranslator.cachedReading
            )
        )
    }

    public static func prepare(for terms: [String]) async -> SpeechSessionVocabulary {
        await SpeechPhoneticTranslator.prewarm(terms: terms)
        return usingCachedReadings(for: terms)
    }
}

nonisolated enum SpeechVocabulary {
    private static let maxContextualStrings = 100

    static func terms(from raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in raw {
            for term in SpeechContextualTerms.candidates(from: value)
            where isUsable(term) && seen.insert(term.lowercased()).inserted {
                result.append(term)
            }
        }
        return result
    }

    static func readings(for term: String, modelReading: String? = nil) -> [String] {
        guard containsASCIILettersWithoutHangul(term) else { return isHangul(term) ? [term] : [] }
        var readings: [String] = []
        let ruleBased = EnglishKoreanPhonetic.transliterate(term).flatMap(hangulOnly)
        if let ruleBased { readings.append(ruleBased) }
        readings.append(contentsOf: spelledOut(term))
        if let ruleBased, let model = modelReading.flatMap(hangulOnly),
           soundsAlike(model, ruleBased) {
            readings.append(model)
        }
        var seen = Set<String>()
        return readings.filter {
            $0.filter { !$0.isWhitespace }.count >= 2 && seen.insert($0).inserted
        }
    }

    static func replacements(
        for terms: [String], modelReading: (String) -> String? = { _ in nil }
    ) -> [String: String] {
        var result: [String: String] = [:]
        var ambiguous = Set<String>()
        for term in terms where isRestorable(term) {
            for reading in readings(for: term, modelReading: modelReading(term)) {
                guard !ambiguous.contains(reading) else { continue }
                if let existing = result[reading], existing != term {
                    result.removeValue(forKey: reading)
                    ambiguous.insert(reading)
                } else {
                    result[reading] = term
                }
            }
        }
        return result
    }

    static func contextualStrings(
        for terms: [String], modelReading: (String) -> String? = { _ in nil }
    ) -> [String] {
        let readingLists = terms.map { readings(for: $0, modelReading: modelReading($0)) }
        let primary = readingLists.compactMap(\.first)
        let alternates = readingLists.flatMap { $0.dropFirst() }
        var seen = Set<String>()
        return (terms + primary + alternates)
            .filter { seen.insert($0).inserted }
            .prefix(maxContextualStrings)
            .map { $0 }
    }

    static func containsASCIILettersWithoutHangul(_ term: String) -> Bool {
        term.contains { $0.isASCII && $0.isLetter } && !term.contains(where: isHangulCharacter)
    }

    private static func isHangul(_ term: String) -> Bool {
        term.contains(where: isHangulCharacter) && !term.contains { $0.isASCII && $0.isLetter }
    }

    private static func isRestorable(_ term: String) -> Bool {
        if isHangul(term) { return term.filter(isHangulCharacter).count >= 2 }
        let letters = term.filter { $0.isASCII && $0.isLetter }
        guard !term.contains("/") else { return false }
        if letters.count >= 2, term.contains(where: \.isNumber), isFormula(term) {
            return true
        }
        return letters.count >= 3 && !(letters.count <= 3 && letters == letters.lowercased())
    }

    private static func isUsable(_ term: String) -> Bool {
        let tokens = term.split(separator: " ")
        let hasMixedScript = term.contains(where: isHangulCharacter)
            && term.contains { $0.isASCII && $0.isLetter }
        guard (1...40).contains(term.count), (1...4).contains(tokens.count),
              term.contains(where: { $0.isLetter }), !hasMixedScript
        else { return false }
        let allowedSymbols: Set<Character> = [" ", "-", "/", ".", "%", "µ", "°", "+", "'"]
        guard term.allSatisfy({
            ($0.isASCII && ($0.isLetter || $0.isNumber)) || isHangulCharacter($0)
                || allowedSymbols.contains($0)
        }) else { return false }
        return tokens.allSatisfy { token in
            !(token.contains(where: \.isNumber) && token.contains { $0.isASCII && $0.isLetter })
                || isFormula(String(token))
        }
    }

    private static func isFormula(_ token: String) -> Bool {
        token.range(of: "^(?:[A-Z][a-z]?[0-9]*)(?:-?[A-Z][a-z]?[0-9]*|-?[0-9]+)*$",
                    options: .regularExpression) != nil
    }

    private static func spelledOut(_ term: String) -> [String] {
        let tokens = term.split(separator: " ")
        guard tokens.count == 1, let token = tokens.first else { return [] }
        let compact = token.filter { $0 != "-" }
        guard (2...6).contains(compact.count),
              token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
              !token.contains("-") || isFormula(String(token)),
              token.contains(where: \.isUppercase),
              token.filter(\.isUppercase).count >= 2 || isFormula(String(token)) else {
            return []
        }
        return digitNames.map { names in
            compact.lowercased().compactMap { character in
                EnglishKoreanPhonetic.letterNames[character] ?? names[character]
            }.joined()
        }.filter { !$0.isEmpty }
    }

    private static func hangulOnly(_ value: String) -> String? {
        let trimmed = value.replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy({ isHangulCharacter($0) || $0 == " " }) else { return nil }
        return trimmed.split(separator: " ").joined(separator: " ")
    }

    static func soundsAlike(_ lhs: String, _ rhs: String) -> Bool {
        let left = SpeechTermMatcher.symbols(of: lhs)
        let right = SpeechTermMatcher.symbols(of: rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return SpeechTermMatcher.distance(left, right, limit: 0.5) <= 0.5
    }

    private static func isHangulCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
    }

    private static let digitNames: [[Character: String]] = [
        ["0": "영", "1": "일", "2": "이", "3": "삼", "4": "사", "5": "오",
         "6": "육", "7": "칠", "8": "팔", "9": "구"],
        ["0": "제로", "1": "원", "2": "투", "3": "쓰리", "4": "포", "5": "파이브",
         "6": "식스", "7": "세븐", "8": "에잇", "9": "나인"]
    ]
}
