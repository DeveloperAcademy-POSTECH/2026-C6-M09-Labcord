import Foundation

/// 고정된 Python pairwise 9열과 HGB v4 32열의 순서를 보존합니다.
nonisolated enum R117HandcraftedFeatures {
    struct Document {
        private let source: [Unicode.Scalar]

        init(text: String) {
            source = Array(text.unicodeScalars)
        }

        func nine(span: R117CandidateSpan) throws -> [Double] {
            try validate(source, span: span)
            return R117HandcraftedFeatures.nine(source: source, span: span, contextRadius: 180)
        }

        func combined32(span: R117CandidateSpan) throws -> [Double] {
            try validate(source, span: span)
            let base = R117HandcraftedFeatures.nine(
                source: source, span: span, contextRadius: 160
            )
            let before = string(source, max(0, span.start - 32), span.start)
            let after = string(source, span.end, min(source.count, span.end + 32))
            // 원본 34열 중 excerpt 경계 flag 두 열(19,20)을 제외합니다.
            let categories = surfaceFeatures(span.surface) + neighborFeatures(
                before: before, after: after, term: span.surface
            )
            let result = base + categories
            guard result.count == 32, result.allSatisfy(\.isFinite) else {
                throw R117ScoringError.invalidFeatures
            }
            return result
        }
    }

    static func nine(text: String, span: R117CandidateSpan) throws -> [Double] {
        try Document(text: text).nine(span: span)
    }

    static func combined32(text: String, span: R117CandidateSpan) throws -> [Double] {
        try Document(text: text).combined32(span: span)
    }

    private static func nine(
        source: [Unicode.Scalar], span: R117CandidateSpan, contextRadius: Int
    ) -> [Double] {
        let scalars = Array(span.surface.unicodeScalars)
        let before = string(source, max(0, span.start - contextRadius), span.start)
        let after = string(source, span.end, min(source.count, span.end + contextRadius))
        let context = before + span.surface + after
        let normalizedSurface = normalized(span.surface)
        return [
            log1p(Double(normalizedSurface.unicodeScalars.count)),
            log1p(Double(max(1, words(scalars)))),
            flag(scalars.contains(where: isDigit)),
            flag(scalars.contains { $0.properties.isUppercase }),
            flag(scalars.contains { "-/+()[]{}=:%".unicodeScalars.contains($0) }),
            flag(scalars.contains { (0xAC00...0xD7A3).contains($0.value) }),
            flag(matches(Pattern.domain, in: context)),
            flag(matches(Pattern.step, in: before)),
            flag(matches(Pattern.heading, in: String(before.unicodeScalars.suffix(100))))
        ]
    }

    private static func surfaceFeatures(_ term: String) -> [Double] {
        let scalars = Array(term.unicodeScalars)
        let cased = scalars.filter { $0.properties.isCased }
        return [
            flag(scalars.contains { (0x0370...0x03FF).contains($0.value) }),
            flag(scalars.contains { (0xAC00...0xD7A3).contains($0.value) }),
            flag(scalars.contains { $0.isASCII && $0.properties.isAlphabetic }),
            flag(scalars.contains(where: isDigit)),
            flag(!cased.isEmpty && cased.allSatisfy { $0.properties.isUppercase }),
            flag(matches(Pattern.alphanumeric, in: term)),
            flag(scalars.contains { "-‐‑–−/+·".unicodeScalars.contains($0) }),
            flag(scalars.contains { "()[]{}（）".unicodeScalars.contains($0) }),
            flag(scalars.contains { "µμΩ°℃".unicodeScalars.contains($0) }),
            flag(words(scalars) > 1)
        ]
    }

    private static func neighborFeatures(
        before: String, after: String, term: String
    ) -> [Double] {
        let last = before.unicodeScalars.last
        let first = after.unicodeScalars.first
        let punctuation = ".,;:!?)]}、。；：！？”’"
        let context = before + after
        return [
            flag(last.map(isWhitespace) ?? false), flag(first.map(isWhitespace) ?? false),
            flag(contains(last, in: punctuation)), flag(contains(first, in: punctuation)),
            flag(contains(last, in: "([{（「『")), flag(contains(first, in: ")]｝」』")),
            flag(last.map(isAlphanumeric) ?? false), flag(first.map(isAlphanumeric) ?? false),
            flag(before.contains("\n")), flag(after.contains("\n")),
            log1p(Double(occurrences(term, in: before) + occurrences(term, in: after))),
            flag(matches(Pattern.action, in: context)),
            flag(matches(Pattern.quantity, in: context))
        ]
    }

    private static func validate(_ source: [Unicode.Scalar], span: R117CandidateSpan) throws {
        guard span.start >= 0, span.end > span.start, span.end <= source.count,
              Array(source[span.start..<span.end]) == Array(span.surface.unicodeScalars) else {
            throw R117ScoringError.invalidSourceSpan
        }
    }

    private static func normalized(_ value: String) -> String {
        let scalars = value.precomposedStringWithCompatibilityMapping.lowercased().unicodeScalars
        return String(String.UnicodeScalarView(scalars.filter(isAlphanumeric)))
    }

    private static func string(_ source: [Unicode.Scalar], _ start: Int, _ end: Int) -> String {
        String(String.UnicodeScalarView(source[start..<end]))
    }

    private static func flag(_ value: Bool) -> Double { value ? 1 : 0 }

    private static func contains(_ scalar: Unicode.Scalar?, in value: String) -> Bool {
        scalar.map { value.unicodeScalars.contains($0) } ?? false
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.numericType == .decimal || scalar.properties.numericType == .digit
    }

    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter,
             .otherLetter, .decimalNumber, .letterNumber, .otherNumber: true
        default: false
        }
    }

    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace || (0x1C...0x1F).contains(scalar.value)
    }

    private static func words(_ scalars: [Unicode.Scalar]) -> Int {
        scalars.split(whereSeparator: isWhitespace).count
    }

    private static func occurrences(_ term: String, in text: String) -> Int {
        let needle = Array(term.unicodeScalars)
        let source = Array(text.unicodeScalars)
        guard !needle.isEmpty, needle.count <= source.count else { return 0 }
        var count = 0
        var position = 0
        while position <= source.count - needle.count {
            if source[position..<(position + needle.count)].elementsEqual(needle) {
                count += 1
                position += needle.count
            } else {
                position += 1
            }
        }
        return count
    }

    private enum Pattern {
        static let domain = expression(
            "(?:method|materials|procedure|protocol|step|실험|방법|시약|재료|장비|분석|측정)",
            insensitive: true
        )
        static let step = expression(
            "(?:^|\\n)\\s*(?:\\d+(?:\\.\\d+)*[.)]?|[A-Z][.)]|[가-힣][.)])\\s"
        )
        static let heading = expression("(?:^|\\n)\\s*[^\\n]{2,90}\\s*(?:\\n|$)")
        static let alphanumeric = expression("[A-Za-z]\\d|\\d[A-Za-z]")
        static let action = expression(
            "\\b(?:add|mix|use|using|measure|transfer|prepare|incubate|centrifuge)\\b" +
                "|첨가|혼합|사용|측정|이동|준비|배양|원심",
            insensitive: true
        )
        static let quantity = expression(
            "\\d\\s*(?:mL|μL|µL|mg|kg|nm|mm|rpm|°C|℃|%|분|시간|초)\\b",
            insensitive: true
        )
    }

    private static func expression(
        _ pattern: String, insensitive: Bool = false
    ) -> NSRegularExpression? {
        let options: NSRegularExpression.Options = insensitive ? [.caseInsensitive] : []
        // Python \b excludes combining marks and joiners; ICU's default \w includes them.
        let word = "[\\p{L}\\p{N}_]"
        let boundary = "(?:(?<!\(word))(?=\(word))|(?<=\(word))(?!\(word)))"
        let whitespace = "[\\p{Z}\\x{0009}-\\x{000D}\\x{001C}-\\x{001F}\\x{0085}]"
        let pythonPattern = pattern.replacingOccurrences(of: "\\b", with: boundary)
            .replacingOccurrences(of: "\\s", with: whitespace)
        return try? NSRegularExpression(pattern: pythonPattern, options: options)
    }

    private static func matches(_ regex: NSRegularExpression?, in text: String) -> Bool {
        regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
