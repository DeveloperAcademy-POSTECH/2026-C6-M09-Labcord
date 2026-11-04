import Foundation

nonisolated public enum PreprocessError: Error { case surrogate, normBudget, partition, checksum }

nonisolated public enum TermPreprocessor {

  static func isCanonicallyComposed(_ sourceScalars: String.UnicodeScalarView) -> Bool {
    let scalarCount = String(String.UnicodeScalarView(sourceScalars))
      .decomposedStringWithCanonicalMapping.precomposedStringWithCanonicalMapping
    return Array(scalarCount.unicodeScalars) == Array(sourceScalars)
  }
  static func canonicalComposition(_ sourceScalars: String.UnicodeScalarView) -> [Unicode.Scalar] {
    Array(
      String(String.UnicodeScalarView(sourceScalars))
        .decomposedStringWithCanonicalMapping
        .precomposedStringWithCanonicalMapping
        .unicodeScalars)
  }

  public static func projectTokens(_ text: String, rawOffsets: [(Int, Int)], unsafe: [Bool])
    -> (projected: [(Int, Int)?], reasons: [[String]]) {
    let scalars = Array(text.unicodeScalars)
    let scalarCount = scalars.count
    var projected = [(Int, Int)?](repeating: nil, count: rawOffsets.count)
    var reasons = [[String]](repeating: [], count: rawOffsets.count)
    var valid: [Int] = []
    for (tokenIndex, pair) in rawOffsets.enumerated() {
      var (startScalarIndex, endScalarIndex) = pair
      guard startScalarIndex >= 0, endScalarIndex > startScalarIndex,
        endScalarIndex <= scalarCount else {
        reasons[tokenIndex].append("invalid_or_zero_raw_offset")
        continue
      }
      let tokenScalars = scalars[startScalarIndex..<endScalarIndex]
      if !tokenScalars.allSatisfy({ $0.properties.isWhitespace }) {
        while startScalarIndex < endScalarIndex
          && scalars[startScalarIndex].properties.isWhitespace {
          startScalarIndex += 1
        }
        while endScalarIndex > startScalarIndex
          && scalars[endScalarIndex - 1].properties.isWhitespace {
          endScalarIndex -= 1
        }
      }
      projected[tokenIndex] = (startScalarIndex, endScalarIndex)
      valid.append(tokenIndex)
      if unsafe[startScalarIndex] || unsafe[endScalarIndex] {
        reasons[tokenIndex].append("grapheme_boundary_risk")
      }
    }
    var maximumTokenEnd = -1
    for tokenIndex in valid {
      let (startScalarIndex, endScalarIndex) = rawOffsets[tokenIndex]
      if startScalarIndex < maximumTokenEnd {
        reasons[tokenIndex].append("raw_overlap_or_unordered")
      }
      maximumTokenEnd = max(maximumTokenEnd, endScalarIndex)
    }
    var minimumTokenStart = scalarCount + 1
    for tokenIndex in valid.reversed() {
      let (startScalarIndex, endScalarIndex) = rawOffsets[tokenIndex]
      if endScalarIndex > minimumTokenStart
        && !reasons[tokenIndex].contains("raw_overlap_or_unordered") {
        reasons[tokenIndex].append("raw_overlap_or_unordered")
      }
      minimumTokenStart = min(minimumTokenStart, startScalarIndex)
    }
    return (projected, reasons)
  }

  nonisolated public struct LedgerWindow {
    public let sourceTokenIndices: [Int]
    public let unitIndices: [Int]
    public let coreMask: [Bool]
    public let tokenIndices: [Int]
    public let relativeStarts: [Double]
    public let relativeEnds: [Double]
    public let mapped: [Int]
  }

}
