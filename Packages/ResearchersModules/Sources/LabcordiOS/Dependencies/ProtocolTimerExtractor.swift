import Foundation

/// 명확한 지속시간을 초로 통일하고, 처음 나온 순서대로 중복 없이 반환합니다.
nonisolated public enum ProtocolTimerExtractor {
    private static let units =
        "(?:hours?|hrs?|hr|h|minutes?|mins?|min|m|seconds?|secs?|sec|s|시간|분|초)"
    private static let number = "(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\\.[0-9]+)?"
    private static let horizontalSpace = "[ \\t]*"
    private static let itemPattern =
        "(?<![0-9.,:])(\(number))\(horizontalSpace)(\(units))(?![A-Za-z])"
    private static let rangePattern =
        "(?<![0-9.,:])\(number)\(horizontalSpace)\(units)?" +
        "(?:\(horizontalSpace)\(number)\(horizontalSpace)\(units)){0,2}" +
        "\(horizontalSpace)(?:~|〜|–|—|-|\\bto\\b|에서|부터)\(horizontalSpace)" +
        "\(number)\(horizontalSpace)\(units)" +
        "(?:\(horizontalSpace)\(number)\(horizontalSpace)\(units)){0,2}(?![A-Za-z])"
    private static let durationPattern =
        "(?<![0-9.,:])\(number)\(horizontalSpace)\(units)" +
        "(?:\(horizontalSpace)\(number)\(horizontalSpace)\(units)){0,2}(?![A-Za-z])"
    private static let conditionPatterns = [
        "\(durationPattern)\(horizontalSpace)(?:이상|이하|이내|미만|초과|정도|가량|내외|전후)",
        "(?<![가-힣A-Za-z])(?:최소|최대|적어도|길어도|약)" +
            "\(horizontalSpace)\(durationPattern)",
        "\\b(?:at least|at most|up to|more than|less than|no more than|no less than|" +
            "minimum(?: of)?|maximum(?: of)?|about|approximately|around)" +
            "[ \\t]+\(durationPattern)",
        "\(durationPattern)[ \\t]+(?:or more|or less|or longer|or shorter)\\b"
    ]
    private static let physicalUnitPattern =
        "\(number)\(horizontalSpace)[A-Za-zµμ]+(?:\\^?[+−-]?[0-9]+)?" +
        "\(horizontalSpace)(?:[/·⋅*]\(horizontalSpace)[A-Za-zµμ]+" +
        "(?:\\^?[+−-]?[0-9]+)?|[ \\t]+[A-Za-zµμ]+(?:\\^[+−-]?[0-9]+|[−-][0-9]+)" +
        "|\\^[+−-]?[0-9]+|[−-][0-9]+|[23](?![0-9A-Za-z]))"
    private static let clockPattern =
        "(?<![0-9:])([0-9]{1,3}):([0-5][0-9]):([0-5][0-9])(?![0-9:])"

    public static func extract(from text: String) -> [Int] {
        // 전각 숫자와 ㎜·㎡·⁻¹ 등을 비교 가능한 표기로 바꾸되 원본 문서는 수정하지 않습니다.
        let text = text.precomposedStringWithCompatibilityMapping
        guard let itemRegex = regex(itemPattern), let physicalRegex = regex(physicalUnitPattern),
              let clockRegex = regex(clockPattern) else { return [] }
        let fullRange = NSRange(text.startIndex..., in: text)
        let clocks = clockRegex.matches(in: text, range: fullRange)
        // 범위의 양 끝과 복합 물리 단위를 개별 고정 타이머로 만들지 않습니다.
        let physical = physicalRegex.matches(in: text, range: fullRange).map(\.range)
        let excluded = reviewRanges(text, physical: physical) + physical + clocks.map(\.range)
        var tokens = itemRegex.matches(in: text, range: fullRange).compactMap { match -> Token? in
            guard !excluded.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                  !isFalsePositive(text, range: match.range),
                  let value = string(in: text, match: match, group: 1),
                  let unit = string(in: text, match: match, group: 2),
                  let total = seconds(value, unit: unit),
                  let scale = multiplier(for: unit) else { return nil }
            return Token(range: match.range, seconds: total, scale: scale)
        }
        tokens += clocks.compactMap { match in
            guard !isClockTime(text, range: match.range),
                  let hours = integer(in: text, match: match, group: 1),
                  let minutes = integer(in: text, match: match, group: 2),
                  let seconds = integer(in: text, match: match, group: 3) else { return nil }
            return Token(
                range: match.range, seconds: hours * 3_600 + minutes * 60 + seconds, scale: 0
            )
        }
        return combinedDurations(tokens.sorted { $0.range.location < $1.range.location }, text)
    }

    /// 범위·상한·하한·근삿값은 원문을 확인해 타이머를 직접 정하도록 알립니다.
    public static func needsManualReview(in text: String) -> Bool {
        let text = text.precomposedStringWithCompatibilityMapping
        guard let physicalRegex = regex(physicalUnitPattern) else { return false }
        let fullRange = NSRange(text.startIndex..., in: text)
        let physical = physicalRegex.matches(in: text, range: fullRange).map(\.range)
        return !reviewRanges(text, physical: physical).isEmpty
    }

    private static func reviewRanges(_ text: String, physical: [NSRange]) -> [NSRange] {
        let fullRange = NSRange(text.startIndex..., in: text)
        guard let itemRegex = regex(itemPattern) else { return [] }
        let patterns = [rangePattern] + conditionPatterns
        return patterns.flatMap { pattern -> [NSRange] in
            guard let expression = regex(pattern) else { return [] }
            return expression.matches(in: text, range: fullRange).compactMap { match in
                // 범위의 마지막 m 뒤에 /s·제곱 등이 이어지면 시간 범위가 아닙니다.
                let physicalOverlap = physical.contains {
                    NSIntersectionRange($0, match.range).length > 0
                        && NSIntersectionRange($0, match.range) != $0
                }
                guard !physicalOverlap else { return nil }
                let items = itemRegex.matches(in: text, range: match.range)
                guard let last = items.last else { return nil }
                let durationRange = NSRange(
                    location: match.range.location,
                    length: NSMaxRange(last.range) - match.range.location
                )
                guard !isFalsePositive(text, range: durationRange) else { return nil }
                return match.range
            }
        }
    }

    private struct Token {
        let range: NSRange
        let seconds: Int
        let scale: Int
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }

    private static func combinedDurations(_ tokens: [Token], _ text: String) -> [Int] {
        let source = text as NSString
        var result: [Int] = []
        var seen = Set<Int>()
        var total = 0
        var previous: Token?
        var overflow = false
        func flush() {
            if !overflow, total > 0, seen.insert(total).inserted { result.append(total) }
            total = 0
            overflow = false
        }
        for token in tokens {
            let joins: Bool
            if let previous, previous.scale > token.scale, token.scale > 0 {
                let gap = NSRange(
                    location: NSMaxRange(previous.range),
                    length: token.range.location - NSMaxRange(previous.range)
                )
                joins = source.substring(with: gap).allSatisfy { $0 == " " || $0 == "\t" }
            } else {
                joins = false
            }
            if !joins { flush() }
            let sum = total.addingReportingOverflow(token.seconds)
            total = sum.partialValue
            overflow = overflow || sum.overflow
            previous = token
        }
        flush()
        return result
    }

    private static func isClockTime(_ text: String, range: NSRange) -> Bool {
        let source = text as NSString
        let prefixStart = max(0, range.location - 24)
        let prefix = source.substring(with: NSRange(
            location: prefixStart, length: range.location - prefixStart
        ))
        let suffix = source.substring(with: NSRange(
            location: NSMaxRange(range), length: min(20, source.length - NSMaxRange(range))
        ))
        return prefix.range(of: "(?:오전|오후|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T])\\s*$",
                            options: [.regularExpression, .caseInsensitive]) != nil
            || suffix.range(of: "^(?:\\.[0-9]+|\\s*(?:AM|PM|기록|시각|[/·⋅*^]))",
                            options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isFalsePositive(_ text: String, range: NSRange) -> Bool {
        let source = text as NSString
        // 단일 대문자 M·H·S는 몰농도·헨리·지멘스 등의 단위와 구분합니다.
        let matched = source.substring(with: range)
        if let last = matched.last, ["M", "H", "S"].contains(last) { return true }
        if matched.last == "m",
           let metre = Range(NSRange(location: NSMaxRange(range) - 1, length: 1), in: text),
           ProtocolDocumentUnitExtractor.isMetre(at: metre, in: text) { return true }
        if range.location > 0 {
            let previous = source.substring(with: NSRange(location: range.location - 1, length: 1))
            if previous == "-" || previous == "−" || previous == "/" { return true }
            if previous.range(of: "[A-Za-z]", options: .regularExpression) != nil {
                let prefix = source.substring(to: range.location)
                let precedingDuration = "\(number)\(horizontalSpace)\(units)$"
                if prefix.range(of: precedingDuration,
                                options: [.regularExpression, .caseInsensitive]) == nil {
                    return true
                }
            }
        }
        let suffix = source.substring(with: NSRange(
            location: NSMaxRange(range), length: min(32, source.length - NSMaxRange(range))
        ))
        if suffix.range(of: "^[ \\t]*(?:[/·⋅*^]|[−-][0-9]|당|의|protein|proteasome|" +
                        "ribosomal|rRNA|단백질|길이|높이|거리|너비)",
                        options: [.regularExpression, .caseInsensitive]) != nil { return true }
        guard let first = suffix.unicodeScalars.first,
              (0xAC00...0xD7A3).contains(first.value) else { return false }
        return suffix.range(of: "^(?:간|동안|후|전|이상|이하|이내|정도|가량|까지|씩|을|를|에|은|는|이|가|으로|로)",
                            options: .regularExpression) == nil
    }

    private static func integer(
        in text: String, match: NSTextCheckingResult, group: Int
    ) -> Int? {
        string(in: text, match: match, group: group).flatMap(Int.init)
    }

    private static func string(
        in text: String, match: NSTextCheckingResult, group: Int
    ) -> String? {
        guard let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    private static func seconds(_ value: String, unit: String) -> Int? {
        guard let scale = multiplier(for: unit),
              let number = Decimal(string: value.replacingOccurrences(of: ",", with: ""),
                                   locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let product = NSDecimalNumber(decimal: number)
            .multiplying(by: NSDecimalNumber(value: scale))
        let rounded = product.rounding(accordingToBehavior: NSDecimalNumberHandler(
            roundingMode: .plain, scale: 0, raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false
        ))
        guard product == rounded, product.compare(NSDecimalNumber.zero) != .orderedAscending,
              product.compare(NSDecimalNumber(value: Int.max)) != .orderedDescending else {
            return nil
        }
        return product.intValue
    }

    private static func multiplier(for unit: String) -> Int? {
        switch unit.lowercased() {
        case "시간", "h", "hr", "hrs", "hour", "hours": 3_600
        case "분", "m", "min", "mins", "minute", "minutes": 60
        case "초", "s", "sec", "secs", "second", "seconds": 1
        default: nil
        }
    }
}
