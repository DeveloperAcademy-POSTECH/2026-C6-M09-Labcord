import Foundation

/// 좌표는 UTF-16이나 Swift Character가 아닌 Python Unicode scalar 기준입니다.
nonisolated struct R117SelectionCandidate: Equatable, Sendable {
    let id: String
    let text: String
    let start: Int
    let end: Int
    /// 괄호 정의를 고를 때 사용하는 frozen9 점수입니다.
    let frozenScore: Double
    let mentions: [Range<Int>]
}

nonisolated enum R117SelectionError: Error {
    case invalidSpan
    case misalignedScores
    case nonfiniteScore
}

nonisolated enum R117SelectionNormalization {
    static func key(_ text: String) -> String {
        let normalized = text.precomposedStringWithCompatibilityMapping.lowercased()
        let allowed = normalized.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter,
                 .otherLetter, .decimalNumber, .letterNumber, .otherNumber:
                return true
            default:
                return false
            }
        }
        return String(String.UnicodeScalarView(allowed))
    }

    static func trim(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        let trimmed = scalars.drop(while: isWhitespace)
            .reversed().drop(while: isWhitespace).reversed()
        return String(String.UnicodeScalarView(trimmed))
    }

    static func isWhitespace(_ scalar: UnicodeScalar) -> Bool {
        scalar.properties.isWhitespace || (0x1C...0x1F).contains(scalar.value)
    }
}
