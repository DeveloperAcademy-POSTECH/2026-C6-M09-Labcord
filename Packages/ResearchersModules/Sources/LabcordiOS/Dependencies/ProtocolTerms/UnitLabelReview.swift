import Foundation

nonisolated enum UnitLabelReview {
    private static let ionicChargeRegex = try? NSRegularExpression(pattern: #"^[0-9]+[+−-]$"#)
    private static let definedVariableRegex = try? NSRegularExpression(
        pattern: #"(?m)^[ \t]*([A-Z][A-Za-z0-9_]{0,3})[ \t]*=[ \t]*measured\b[^\r\n]{1,120}"#
    )
    private static let trailingReadingRegex = try? NSRegularExpression(
        pattern: #"([0-9]+(?:[.,][0-9]+)?)[ \t]*\z"#
    )
    private static let celsiusReadingRegex = try? NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9.,])([0-9]+(?:[.,][0-9]+)?)[ \t]*°C(?![A-Za-z])"#
    )

    static func apply(to terms: ProtocolExtractedTerms, source: String) -> ProtocolExtractedTerms {
        var result = terms
        let variables = definedVariables(in: source)
        var glossaryKeys = Set(result.glossaryTerms.map(ProtocolTermNormalizer.key))
        result.units = terms.units.filter { term in
            guard !ProtocolTermNormalizer.isUnit(term) else { return true }
            let range = NSRange(term.startIndex..., in: term)
            let isNonUnitToken = ionicChargeRegex?.firstMatch(in: term, range: range) != nil
                || variables.contains(term) || onlyDocumentIdentifier(term, in: source)
            let isCelsiusArtifact = term == "EC" || term == "tEC"
            if isNonUnitToken || isCelsiusArtifact { result.usedFallback = true }
            let shouldMoveToGlossary = isNonUnitToken
                || (isCelsiusArtifact && pairedCelsiusNotation(term, in: source))
            guard shouldMoveToGlossary else {
                return true
            }
            if glossaryKeys.insert(ProtocolTermNormalizer.key(term)).inserted {
                result.glossaryTerms.append(term)
            }
            return false
        }
        return result
    }

    private static func definedVariables(in source: String) -> Set<String> {
        guard let definedVariableRegex else { return [] }
        return Set(definedVariableRegex.matches(
            in: source, range: NSRange(source.startIndex..., in: source))
            .compactMap { match in
                Range(match.range(at: 1), in: source).map { String(source[$0]) }
            })
    }

    private static func onlyDocumentIdentifier(_ term: String, in source: String) -> Bool {
        guard term == "ROM" else { return false }
        let ranges = occurrences(of: term, in: source)
        return !ranges.isEmpty && ranges.allSatisfy {
            source[..<$0.lowerBound].hasSuffix("CD-")
                && !isLetter(source[$0.upperBound...].first)
        }
    }

    private static func pairedCelsiusNotation(_ term: String, in source: String) -> Bool {
        let ranges = occurrences(of: term, in: source).filter { range in
            !isLetter(source[..<range.lowerBound].last)
                && !isLetter(source[range.upperBound...].first)
        }
        guard !ranges.isEmpty else { return false }
        var hasMatchingCelsiusReading = false
        for range in ranges {
            let start = source.index(range.lowerBound, offsetBy: -256,
                                     limitedBy: source.startIndex) ?? source.startIndex
            let end = source.index(range.upperBound, offsetBy: 256,
                                   limitedBy: source.endIndex) ?? source.endIndex
            let surroundingSource = String(source[start..<end])
            if term == "tEC" {
                guard surroundingSource.contains("t°C") else { return false }
                hasMatchingCelsiusReading = true
                continue
            }
            let prefix = String(source[..<range.lowerBound].suffix(32))
            let prefixRange = NSRange(prefix.startIndex..., in: prefix)
            if let match = trailingReadingRegex?.firstMatch(in: prefix, range: prefixRange),
               let value = Range(match.range(at: 1), in: prefix) {
                guard containsCelsius(String(prefix[value]), in: surroundingSource)
                else { return false }
                hasMatchingCelsiusReading = true
            } else {
                let line = source[source.lineRange(for: range)]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let counterpart = line.replacingOccurrences(of: "EC", with: "°C")
                let lines = surroundingSource.components(separatedBy: .newlines).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard lines.contains(counterpart) else { return false }
            }
        }
        return hasMatchingCelsiusReading
    }

    private static func containsCelsius(_ value: String, in source: String) -> Bool {
        guard let celsiusReadingRegex else { return false }
        return celsiusReadingRegex.matches(
            in: source, range: NSRange(source.startIndex..., in: source))
            .contains { match in
                guard let range = Range(match.range(at: 1), in: source) else { return false }
                return source[range] == value
            }
    }

    private static func occurrences(
        of term: String, in source: String
    ) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = source.startIndex
        while let range = source.range(of: term, range: start..<source.endIndex) {
            ranges.append(range)
            start = range.upperBound
        }
        return ranges
    }

    private static func isLetter(_ character: Character?) -> Bool {
        guard let character, character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else { return false }
        return (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }
}
