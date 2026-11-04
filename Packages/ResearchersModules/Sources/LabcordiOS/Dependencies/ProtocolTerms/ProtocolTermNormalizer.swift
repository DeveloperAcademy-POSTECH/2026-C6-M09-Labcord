import Foundation

/// 용어 비교와 단위 판별에 쓰는 표기 규칙입니다.
nonisolated public enum ProtocolTermNormalizer {
    private static let unitPattern = """
        ^(?:[0-9.,]+\\s*)?(?:\
        (?:[pnµμumck]|da)?(?:l|L|g|M|mol|m)|\
        mg/ml|mg/mL|µg/ml|µg/mL|ug/ml|ng/ml|ng/µl|ng/µL|\
        °C|℃|°F|K|rpm|×\\s?g|x\\s?g|g-force|%|v/v|w/v|w/w|ppm|ppb|\
        h|hr|hrs|min|sec|s|ms|kDa|Da|bp|kb|nt|U|IU|OD|pH|V|mA|W|Hz|kHz|siemens|psi|bar|atm|Pa|kPa\
        )$
        """

    public static func key(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if isUnit(trimmed) { return ProtocolDocumentUnitExtractor.key(trimmed) }
        return trimmed.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }

    static func isUnit(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return false }
        return ProtocolDocumentUnitExtractor.isUnit(trimmed)
            || trimmed.range(of: unitPattern, options: .regularExpression) != nil
    }
}
