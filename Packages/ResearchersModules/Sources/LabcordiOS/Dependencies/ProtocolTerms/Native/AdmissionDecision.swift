import Foundation

/// Diagnostic-only shared admission policy for the frozen v3 decoder.
///
/// This intentionally mirrors TermHintDecoder's current guard.  It does not
/// relax English mid-word filtering; it only returns an auditable reason so a
/// raw exporter and an inference exporter cannot drift.
nonisolated struct AdmissionDecision: Codable, Equatable {
  let admitted: Bool
  let retained: Bool
  let reason: String
  let kind: String
  let tier: Int
  let ordinal: Int
  let noFilter: Bool
  let midLeft: Bool
  let midRight: Bool
  let start: Int
  let end: Int
  let norm: String

  static func isL(_ scalar: Unicode.Scalar) -> Bool {
    CharacterSet.letters.contains(scalar)
  }

  static func isN(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .decimalNumber, .letterNumber, .otherNumber: return true
    default: return false
    }
  }

  static func decide(_ input: AdmissionInput) -> AdmissionDecision {
    let chars = input.chars
    let language = input.language
    let start = input.start
    let end = input.end
    let score = input.score
    let noFilter = input.noFilter
    let kind = input.kind
    let tier = input.tier
    let ordinal = input.ordinal
    let norm = input.norm
    let valid = start >= 0 && start < end && end <= chars.count && score.isFinite
    guard valid else {
      return AdmissionDecision(
        admitted: false, retained: false,
        reason: "invalid_span_or_score", kind: kind,
        tier: tier, ordinal: ordinal, noFilter: noFilter,
        midLeft: false, midRight: false,
        start: start, end: end, norm: "")
    }

    let midLeft = start > 0 && (isL(chars[start - 1]) || isN(chars[start - 1]))
    let midRight = end < chars.count && (isL(chars[end]) || isN(chars[end]))
    // Frozen v3 behavior: language == ko || noFilter || !(midLeft || midRight)
    let admitted = language == "ko" || noFilter || !(midLeft || midRight)
    let reason: String
    if !admitted {
      if midLeft && midRight {
        reason = "english_mid_word_left_and_right"
      } else if midLeft {
        reason = "english_mid_word_left"
      } else {
        reason = "english_mid_word_right"
      }
    } else if language == "ko" {
      reason = "admitted_korean_language_policy"
    } else if noFilter {
      reason = "admitted_no_filter_kind"
    } else {
      reason = norm.isEmpty ? "admitted_but_empty_norm" : "admitted_boundary_safe"
    }
    return AdmissionDecision(
      admitted: admitted, retained: admitted && !norm.isEmpty,
      reason: reason, kind: kind, tier: tier, ordinal: ordinal,
      noFilter: noFilter, midLeft: midLeft, midRight: midRight,
      start: start, end: end, norm: norm)
  }
}

nonisolated struct AdmissionInput {
  let chars: [Unicode.Scalar]
  let language: String
  let start: Int
  let end: Int
  let score: Float
  let noFilter: Bool
  let kind: String = "unknown"
  let tier: Int = 0
  let ordinal: Int = 0
  let norm: String
}
