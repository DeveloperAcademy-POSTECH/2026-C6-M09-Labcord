import Foundation

nonisolated extension TermPreprocessor {
  private static func unsafeBoundaryMap(_ scalars: [Unicode.Scalar]) throws -> [Bool] {
    let count = scalars.count
    for scalar in scalars where (0xD800...0xDFFF).contains(scalar.value) {
      throw PreprocessError.surrogate
    }
    var unsafe = [Bool](repeating: false, count: count + 1)
    for index in 1..<max(1, count) {
      let current = scalars[index]
      let previous = scalars[index - 1]
      let category = current.properties.generalCategory
      let isCombiningMark = category == .nonspacingMark || category == .spacingMark
        || category == .enclosingMark
      let isEmojiModifier = (0x1F3FB...0x1F3FF).contains(current.value)
      let isCurrentRegionalIndicator = (0x1F1E6...0x1F1FF).contains(current.value)
      let isPreviousRegionalIndicator = (0x1F1E6...0x1F1FF).contains(previous.value)
      if isCombiningMark || current.value == 0x200D || previous.value == 0x200D || isEmojiModifier
        || (isCurrentRegionalIndicator && isPreviousRegionalIndicator) {
        unsafe[index] = true
      }
    }
    return unsafe
  }

  private static func normalizedRanges(
    scalars: [Unicode.Scalar], bounds: [Int], unsafe: inout [Bool]
  ) throws -> (stack: [[Unicode.Scalar]], ranges: [(Int, Int)]) {
    var stack: [[Unicode.Scalar]] = []
    var ranges: [(Int, Int)] = []
    var normalizationWork = 0
    for limit in 0..<max(0, bounds.count - 1) {
      let start = bounds[limit]
      let end = bounds[limit + 1]
      var current = canonicalComposition(String.UnicodeScalarView(scalars[start..<end]))
      var lower = start
      let upper = end
      normalizationWork += end - start
      while let last = stack.last, !last.isEmpty, !current.isEmpty {
        let pair = String.UnicodeScalarView([last.last!, current.first!])
        normalizationWork += pair.count
        if isCanonicallyComposed(pair) { break }
        let left = stack.removeLast()
        let previous = ranges.removeLast()
        unsafe[lower] = true
        let combinedScalars = String.UnicodeScalarView(left + current)
        normalizationWork += combinedScalars.count
        current = canonicalComposition(combinedScalars)
        lower = previous.0
        if normalizationWork > 16 * scalars.count + 16 { throw PreprocessError.normBudget }
      }
      stack.append(current)
      ranges.append((lower, upper))
    }
    return (stack, ranges)
  }

  private static func validateSafeRanges(
    _ text: String, stack: [[Unicode.Scalar]], ranges: [(Int, Int)]
  ) throws {
    let joined = String(String.UnicodeScalarView(stack.flatMap { $0 }))
    let normalizedSource = text.decomposedStringWithCanonicalMapping
      .precomposedStringWithCanonicalMapping
    guard Array(joined.unicodeScalars) == Array(normalizedSource.unicodeScalars) else {
      throw PreprocessError.checksum
    }
    let count = text.unicodeScalars.count
    guard ranges.reduce(0, { $0 + $1.1 - $1.0 }) == count,
      ranges.isEmpty || (ranges.first!.0 == 0 && ranges.last!.1 == count)
    else {
      throw PreprocessError.partition
    }
  }

  public static func safeUnits(_ text: String) throws -> SafeUnitResult {
    let scalars = Array(text.unicodeScalars)
    let count = scalars.count
    var unsafe = try unsafeBoundaryMap(scalars)
    let bounds = (0...count).filter { !unsafe[$0] }
    let normalized = try normalizedRanges(scalars: scalars, bounds: bounds, unsafe: &unsafe)
    let offsets = normalized.ranges
    try validateSafeRanges(text, stack: normalized.stack, ranges: offsets)
    var scalarUTF16Offsets = [0]
    for scalar in scalars {
      scalarUTF16Offsets.append(scalarUTF16Offsets.last! + (scalar.value > 0xFFFF ? 2 : 1))
    }
    return SafeUnitResult(offsets: offsets, unsafe: unsafe, scalarUTF16Offsets: scalarUTF16Offsets)
  }
}
