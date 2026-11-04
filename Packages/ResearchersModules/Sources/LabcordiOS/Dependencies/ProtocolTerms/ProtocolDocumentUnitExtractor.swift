import Foundation

nonisolated enum ProtocolDocumentUnitExtractor {
    private static let unitSymbolPattern =
        #"(?:°[CF]|℃|℉|°|%|R\.H\.?|RH|pH|OD(?:600)?|rpm|ppm|ppb|"#
        + #"㎖|㎕|㎛|㎜|㎝|㎞|㎟|㎠|㎡|㎢|㎣|㎤|㎥|㎎|㎏|㎐|㎑|㎒|㎓|㎩|㎪|㎫|"#
        + #"mmHg|cmH2O|ohms?|(?:[fpnµμumcdhkMGT]|da)?"#
        + #"(?:mol|mhos?|Pa|Hz|Da|IU|L|l|g|m|M|V|A|W|N|J|K|S|F|H|Ω|Ω|s)|"#
        + #"bar|atm|psi|bp|kb|nt|U|v/v|w/v|w/w|s|min|h)"#
    private static let unitExponentPattern =
        #"(?:\^[−-]?[1-9]|[−-][1-9]|[23]|[¹²³⁴⁵⁶⁷⁸⁹]|[⁻⁺][¹²³⁴⁵⁶⁷⁸⁹])?"#
    private static let inverseUnitExponentPattern = #"(?:\^[−-][1-9]|[−-][1-9]|⁻[¹²³⁴⁵⁶⁷⁸⁹])"#
    private static let compoundUnitPattern = unitSymbolPattern + unitExponentPattern
        + #"(?:[ \t]*(?:/|·|⋅)[ \t]*"# + unitSymbolPattern + unitExponentPattern
        + #"|[ \t]+"# + unitSymbolPattern + inverseUnitExponentPattern + #")*"#
    private static let percentUnitPattern = #"%(?:[ \t]*(?:R\.H\.?|RH|"#
        + #"\([ \t]*(?:v/v|w/v|w/w)[ \t]*\)))?"#
    private static let expression = #"(?:[×x][ \t]*g|"# + compoundUnitPattern + ")"
    private static let pattern = #"(?<![A-Za-zµμ])(?:"# + percentUnitPattern
        + #"(?![0-9?])|"# + expression + #"(?![A-Za-zµμ0-9?]))"#
    private static let measurementUnitRegex = try? NSRegularExpression(pattern: pattern)
    private static let trailingQuantityRegex = try? NSRegularExpression(
        pattern: #"[0-9]+(?:[.,][0-9]+)*(?:[eE][+−-]?[0-9]+)?[ \t]*\z"#
    )
    private static let documentIdentifierRegex = try? NSRegularExpression(
        pattern: #"\b(?:method|cd-rom|protocol|figure|table|model|catalog|"#
            + #"batch|lot|sample|part|no)"#
            + #"[ \t.#:-]*[0-9]+(?:[.-][0-9]+)*[ \t]*\z"#, options: .caseInsensitive
    )
    private static let unitNameMetadataRegex = try? NSRegularExpression(
        pattern: #"\b(?:author|creator|model|catalog|method|protocol|figure|table|"#
            + #"sample|part|no|lot|batch|filename|file|title)[ \t:#.=−-]*"#
            + #"(?:[0-9]+(?:[.-][0-9]+)*)?[ \t]*\z"#, options: .caseInsensitive
    )
    private static let formulaSuffixRegex = try? NSRegularExpression(
        pattern: #"^(?:\][ \t]*(?:[0-9]|[lo]\b)|-[lI][0o]\b)"#
    )
    private static let measurementHeaderRegex = try? NSRegularExpression(
        pattern: #"(?:\b(?:units?|volume|mass|length|height|width|depth|concentration|"#
            + #"conductivity|conductance)|단위|부피|질량|길이|높이|너비|깊이|농도|전도도)"#
            + #"[ \t]*[:,=]?[ \t]*(?:[(\[][ \t]*)?$"#,
        options: .caseInsensitive
    )
    private static let unitHeaderRegexBySymbol = [
        "A": #"(?:\b(?:current|amperes?)|전류|암페어)"#,
        "N": #"(?:\b(?:normality|force)|노르말|힘|수직항력)"#,
        "K": #"(?:\b(?:temperature|kelvin)|온도|켈빈)"#,
        "S": #"(?:\b(?:conductance|conductivity|siemens)|전도도|컨덕턴스|지멘스)"#,
        "F": #"(?:\b(?:capacitance|farads?)|전기용량|정전용량|패럿)"#,
        "H": #"(?:\b(?:inductance|henrys?|henries)|인덕턴스|헨리)"#,
        "Ω": #"(?:\b(?:resistance|ohms?)|저항|옴)"#
    ].compactMapValues {
        try? NSRegularExpression(
            pattern: $0 + #"[ \t]*[:=]?[ \t]*(?:[(\[][ \t]*)?$"#,
            options: .caseInsensitive
        )
    }
    private static let electricalVariableRegexByUnit = ["F": "C", "H": "L"].compactMapValues {
        try? NSRegularExpression(pattern: #"(?:^|[^A-Za-z])"# + $0 + #"[ \t]*=[ \t]*$"#)
    }
    private static let measurementSymbols: Set<String> = [
        "pH", "RH", "R.H", "R.H.", "OD", "OD600", "rpm", "ppm", "ppb"
    ]
    private static let biologicalSuffixRegex = try? NSRegularExpression(
        pattern: #"^[ \t]*(?:protein|proteasome|ribosomal|rRNA|단백질)"#,
        options: .caseInsensitive
    )
    private static let lowercaseLitreRegex = try? NSRegularExpression(
        pattern: #"(?<![A-Za-zµμ])([fpnµμumcdhkMGT]|da)?l(?![A-Za-zµμ])"#
    )
    private static let asciiMicroPrefixRegex = try? NSRegularExpression(
        pattern: #"(?<![A-Za-zµμ])u(?=(?:mol|mhos?|Pa|Hz|Da|IU|L|l|g|m|M|V|A|W|N|J|K|S|F|H|Ω|Ω|s)"#
            + #"(?![A-Za-zµμ]))"#
    )
    private static let ohmNameRegex = try? NSRegularExpression(
        pattern: #"(?<![A-Za-zµμ])ohms?(?![A-Za-zµμ])"#
    )
    private static let pluralMhoRegex = try? NSRegularExpression(
        pattern: #"(?<![A-Za-zµμ])([fpnµμumcdhkMGT]|da)?mhos(?![A-Za-zµμ])"#
    )
    private static let durationSymbols: Set<String> = ["h", "min", "s"]
    private static let dimensionNamePattern = #"(?:길이|높이|거리|깊이|너비|폭|두께|"#
        + #"\b(?:length|height|distance|depth|width|thickness))"#
    private static let metreQuantityPrefixRegex = try? NSRegularExpression(
        pattern: dimensionNamePattern + #"[ \t]*(?:(?:는|은|가|이|of|is|to|=|:|：)[ \t]*)?"#
            + #"(?:(?:약|about|approximately)[ \t]*)?"#
            + #"[+−-]?[0-9]+(?:[.,][0-9]+)?"#
            + #"(?:[ \t]*(?:~|〜|–|—|-|to)[ \t]*[0-9]+(?:[.,][0-9]+)?)?[ \t]*$"#,
        options: .caseInsensitive
    )
    private static let dimensionSuffixRegex = try? NSRegularExpression(
        pattern: #"^[ \t]*(?:길이|높이|거리|깊이|너비|폭|두께|"#
            + #"(?:in[ \t]+)?(?:length|height|distance|depth|width|thickness|"#
            + #"long|high|deep|wide)\b)"#,
        options: .caseInsensitive
    )

    static func extract(from source: String) -> [String] {
        guard let measurementUnitRegex else { return [] }
        var seen: Set<String> = []
        return measurementUnitRegex.matches(
            in: source, range: NSRange(source.startIndex..., in: source))
            .compactMap { match in
                guard let range = Range(match.range, in: source) else { return nil }
                let unit = String(source[range])
                guard !durationSymbols.contains(unit),
                      isMeasurement(unit, at: range, source: source),
                      seen.insert(key(unit)).inserted else { return nil }
                return unit
            }
    }

    static func supplement(
        _ terms: ProtocolExtractedTerms, from source: String
    ) -> ProtocolExtractedTerms {
        let measured = extract(from: source)
        let measuredKeys = Set(measured.map(key))
        var result = terms
        result.materials.removeAll { measuredKeys.contains(key($0)) }
        result.samples.removeAll { measuredKeys.contains(key($0)) }
        result.glossaryTerms.removeAll { measuredKeys.contains(key($0)) }
        var seen: Set<String> = []
        result.units = (terms.units + measured).filter { seen.insert(key($0)).inserted }
        return UnitLabelReview.apply(to: result, source: source)
    }

    static func isUnit(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let measurementUnitRegex else { return false }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = measurementUnitRegex.firstMatch(in: value, range: range)
        else { return false }
        return match.range == range
    }

    static func isMetre(at range: Range<String.Index>, in source: String) -> Bool {
        let prefix = String(source[..<range.lowerBound].suffix(64))
            .precomposedStringWithCompatibilityMapping
        let suffix = String(source[range.upperBound...].prefix(32))
        let previous = prefix.last { !$0.isWhitespace }
        let next = suffix.first { !$0.isWhitespace }
        if (previous == "(" && next == ")") || (previous == "[" && next == "]") {
            return true
        }
        return metreQuantityPrefixRegex?.firstMatch(in: prefix,
                                       range: NSRange(prefix.startIndex..., in: prefix)) != nil
            || dimensionSuffixRegex?.firstMatch(in: suffix,
                                       range: NSRange(suffix.startIndex..., in: suffix)) != nil
    }

    private static func isMeasurement(
        _ unit: String, at range: Range<String.Index>, source: String
    ) -> Bool {
        if unit == "m" { return isMetre(at: range, in: source) }
        if unit == "ohm" || unit == "ohms" {
            let prefix = String(source[..<range.lowerBound].suffix(64))
            let fullRange = NSRange(prefix.startIndex..., in: prefix)
            return unitNameMetadataRegex?.firstMatch(in: prefix, range: fullRange) == nil
        }
        if measurementSymbols.contains(unit) || unit.contains("%") || unit.contains("°")
            || unit.precomposedStringWithCompatibilityMapping != unit { return true }
        if unit.contains("/") || unit.contains("·") || unit.contains("⋅") { return true }
        let prefix = String(source[..<range.lowerBound].suffix(64))
        let suffix = String(source[range.upperBound...].prefix(32))
        if unit == "S", biologicalSuffixRegex?.firstMatch(
            in: suffix, range: NSRange(suffix.startIndex..., in: suffix)
        ) != nil { return false }
        if formulaSuffixRegex?.firstMatch(in: suffix,
                                     range: NSRange(suffix.startIndex..., in: suffix)) != nil {
            return false
        }
        if unit == "H" || unit == "F", prefix.last?.isNumber == true {
            return hasElectricalQuantityContext(unit, prefix: prefix)
        }
        if hasQuantity(prefix) { return true }
        if let specific = unitHeaderRegexBySymbol[unit] {
            return specific.firstMatch(in: prefix,
                                       range: NSRange(prefix.startIndex..., in: prefix)) != nil
        }
        return isHeader(prefix: prefix, suffix: suffix)
    }

    private static func hasElectricalQuantityContext(_ unit: String, prefix: String) -> Bool {
        let range = NSRange(prefix.startIndex..., in: prefix)
        guard let quantityMatch = trailingQuantityRegex?.firstMatch(in: prefix, range: range),
              let quantityRange = Range(quantityMatch.range, in: prefix) else { return false }
        let context = String(prefix[..<quantityRange.lowerBound])
        let contextRange = NSRange(context.startIndex..., in: context)
        return unitHeaderRegexBySymbol[unit]?.firstMatch(in: context, range: contextRange) != nil
            || electricalVariableRegexByUnit[unit]?.firstMatch(
                in: context, range: contextRange) != nil
    }

    private static func hasQuantity(_ prefix: String) -> Bool {
        let fullRange = NSRange(prefix.startIndex..., in: prefix)
        guard let match = trailingQuantityRegex?.firstMatch(in: prefix, range: fullRange),
              let range = Range(match.range, in: prefix) else { return false }
        if documentIdentifierRegex?.firstMatch(in: prefix, range: fullRange) != nil {
            return false
        }
        if let previous = prefix[..<range.lowerBound].last {
            if previous == ")" || previous == "]" { return false }
            if let scalar = previous.unicodeScalars.first,
               (65...90).contains(scalar.value) || (97...122).contains(scalar.value) {
                return false
            }
        }
        return true
    }

    private static func isHeader(prefix: String, suffix: String) -> Bool {
        let previous = prefix.last { !$0.isWhitespace }
        let next = suffix.first { !$0.isWhitespace }
        if (previous == "(" && next == ")") || (previous == "[" && next == "]") {
            return true
        }
        if previous == ":" || previous == "：" { return true }
        let linePrefix = prefix.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
        let lineSuffix = suffix.split(separator: "\n", omittingEmptySubsequences: false)
            .first ?? ""
        if linePrefix.trimmingCharacters(in: .whitespaces).isEmpty,
           lineSuffix.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return measurementHeaderRegex?.firstMatch(in: prefix,
                                  range: NSRange(prefix.startIndex..., in: prefix)) != nil
    }

    static func key(_ value: String) -> String {
        var key = value.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "µ", with: "μ")
        let replacements = [(lowercaseLitreRegex, "$1L"), (asciiMicroPrefixRegex, "μ"),
                            (ohmNameRegex, "Ω"), (pluralMhoRegex, "$1mho")]
        for (expression, replacement) in replacements {
            if let expression {
                key = expression.stringByReplacingMatches(
                    in: key, range: NSRange(key.startIndex..., in: key),
                    withTemplate: replacement
                )
            }
        }
        return key
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
    }
}
