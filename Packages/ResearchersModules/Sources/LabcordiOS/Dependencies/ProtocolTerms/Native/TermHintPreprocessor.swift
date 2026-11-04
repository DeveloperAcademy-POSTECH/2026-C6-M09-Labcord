// TermHintPreprocessor.swift — character_boundary_data.py source-projection 계약 포트.
// safe_units(NFC 분할) / 토큰 투영 / 윈도우 ledger / char_ids / merge_unit_logits.
import Foundation

nonisolated public enum PreprocessError: Error { case surrogate, normBudget, partition, checksum }

nonisolated public enum TermPreprocessor {
  // NFC가 스칼라 시퀀스를 합성하는지 검사 (Swift == 는 grapheme 기반이므로 스칼라 비교로 판정)
  static func isNFC(_ localString: String.UnicodeScalarView) -> Bool {
    let localCount = String(String.UnicodeScalarView(localString))
      .decomposedStringWithCanonicalMapping.precomposedStringWithCanonicalMapping
    return Array(localCount.unicodeScalars) == Array(localString)
  }
  static func nfc(_ localString: String.UnicodeScalarView) -> [Unicode.Scalar] {
    Array(
      String(String.UnicodeScalarView(localString))
        .decomposedStringWithCanonicalMapping
        .precomposedStringWithCanonicalMapping
        .unicodeScalars)
  }

  /// _source_tokens: raw offset 공백 트림 + unsafe/overlap 이유 표시.
  public static func projectTokens(_ text: String, rawOffsets: [(Int, Int)], unsafe: [Bool])
    -> (projected: [(Int, Int)?], reasons: [[String]]) {
    let scalars = Array(text.unicodeScalars)
    let localCount = scalars.count
    var projected = [(Int, Int)?](repeating: nil, count: rawOffsets.count)
    var reasons = [[String]](repeating: [], count: rawOffsets.count)
    var valid: [Int] = []
    for (localIndex, pair) in rawOffsets.enumerated() {
      var (localStart, localEnd) = pair
      guard localStart >= 0, localEnd > localStart, localEnd <= localCount else {
        reasons[localIndex].append("invalid_or_zero_raw_offset")
        continue
      }
      let seg = scalars[localStart..<localEnd]
      if !seg.allSatisfy({ $0.properties.isWhitespace }) {
        while localStart < localEnd && scalars[localStart].properties.isWhitespace {
          localStart += 1
        }
        while localEnd > localStart && scalars[localEnd - 1].properties.isWhitespace {
          localEnd -= 1
        }
      }
      projected[localIndex] = (localStart, localEnd)
      valid.append(localIndex)
      if unsafe[localStart] || unsafe[localEnd] {
        reasons[localIndex].append("grapheme_boundary_risk")
      }
    }
    var maximum = -1
    for localIndex in valid {
      let (localStart, localEnd) = rawOffsets[localIndex]
      if localStart < maximum { reasons[localIndex].append("raw_overlap_or_unordered") }
      maximum = max(maximum, localEnd)
    }
    var minimum = localCount + 1
    for localIndex in valid.reversed() {
      let (localStart, localEnd) = rawOffsets[localIndex]
      if localEnd > minimum && !reasons[localIndex].contains("raw_overlap_or_unordered") {
        reasons[localIndex].append("raw_overlap_or_unordered")
      }
      minimum = min(minimum, localStart)
    }
    return (projected, reasons)
  }

  nonisolated public struct LedgerWindow {
    public let flatIndices: [Int]
    public let unitIndices: [Int]
    public let coreMask: [Bool]
    public let tokenIndices: [Int]
    public let relStart: [Double]
    public let relEnd: [Double]
    public let mapped: [Int]
  }

}
