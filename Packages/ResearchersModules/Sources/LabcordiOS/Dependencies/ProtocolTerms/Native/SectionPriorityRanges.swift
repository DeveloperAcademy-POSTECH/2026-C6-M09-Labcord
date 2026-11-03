import Foundation

nonisolated extension SectionPriority {
  func ranges(in text: String) -> ([ScalarRange], [PriorityHeading]) {
    let scalars = Array(text.unicodeScalars)
    let lines = lineRanges(scalars)
    var localIndex = 0
    var active: Int?
    var ranges: [ScalarRange] = []
    var headings: [PriorityHeading] = []
    while localIndex < lines.count {
      guard let selected = headingSelection(scalars, lines: lines, at: localIndex) else {
        localIndex += 1
        continue
      }
      if selected.kind == "procedure" {
        if active == nil { active = selected.range.end }
      } else if let localStart = active {
        ranges.append(.init(start: localStart, end: selected.range.start))
        active = nil
      }
      headings.append(
        .init(
          start: selected.range.start, end: selected.range.end,
          kind: selected.kind, heading: selected.raw))
      localIndex += selected.width
    }
    if let localStart = active { ranges.append(.init(start: localStart, end: scalars.count)) }
    return (ranges, headings)
  }

  private func lineRanges(_ scalars: [Unicode.Scalar]) -> [ScalarRange] {
    var lines: [ScalarRange] = []
    var first = 0
    for localIndex in scalars.indices where scalars[localIndex].value == 10 {
      if first < localIndex { lines.append(.init(start: first, end: localIndex)) }
      first = localIndex + 1
    }
    if first < scalars.count { lines.append(.init(start: first, end: scalars.count)) }
    return lines
  }

  private func headingSelection(
    _ scalars: [Unicode.Scalar], lines: [ScalarRange], at localIndex: Int
  ) -> HeadingSelection? {
    for width in [2, 1] {
      guard localIndex + width <= lines.count else { continue }
      let line = lines[localIndex]
      let last = lines[localIndex + width - 1]
      guard width != 2 || last.start == line.end + 1 else { continue }
      let raw = String(String.UnicodeScalarView(scalars[line.start..<last.end]))
      if let selection = headingCandidate(
        raw, range: .init(start: line.start, end: last.end), width: width) { return selection }
    }
    return nil
  }

  private func headingCandidate(
    _ raw: String, range: ScalarRange, width: Int
  ) -> HeadingSelection? {
    let normalized = raw
      .decomposedStringWithCompatibilityMapping
      .precomposedStringWithCompatibilityMapping.lowercased()
    let words = normalized.unicodeScalars.split(whereSeparator: Self.isWhitespace)
    var localString = words.map { String(String.UnicodeScalarView($0)) }.joined(separator: " ")
    localString = localString.trimmingCharacters(in: CharacterSet(charactersIn: "#: "))
    let extra: (String, Int)?
    if localString.unicodeScalars.count > rules.maxHeadingScalars
      || localString.unicodeScalars.split(whereSeparator: Self.isWhitespace).count
        > rules.maxHeadingWords {
      guard legalMatch(raw, width: width) != nil else { return nil }
      extra = extraHeading(raw, width: width)
    } else {
      let all = NSRange(localString.startIndex..<localString.endIndex, in: localString)
      if let localMiddle = prefix.firstMatch(in: localString, range: all),
        let localResult = Range(localMiddle.range, in: localString) {
        localString.removeSubrange(localResult)
      }
      localString = String(
        String.UnicodeScalarView(
          localString.unicodeScalars.drop(while: Self.isWhitespace).reversed().drop(
            while: Self.isWhitespace).reversed()))
      if fullMatch(begin, localString) {
        return HeadingSelection(
          width: width, range: range,
          raw: raw, kind: "procedure")
      }
      if fullMatch(end, localString) {
        return HeadingSelection(
          width: width, range: range,
          raw: raw, kind: "stop")
      }
      extra = extraHeading(raw, width: width)
    }
    guard let (kind, prefixEnd) = extra else { return nil }
    let heading = String(String.UnicodeScalarView(raw.unicodeScalars.prefix(prefixEnd)))
    return HeadingSelection(
      width: width,
      range: .init(start: range.start, end: range.start + prefixEnd),
      raw: heading, kind: kind)
  }
}

nonisolated struct HeadingSelection {
  let width: Int
  let range: ScalarRange
  let raw: String
  let kind: String
}
