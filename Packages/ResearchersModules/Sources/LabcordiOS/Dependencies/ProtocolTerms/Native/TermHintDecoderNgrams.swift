import Foundation

nonisolated extension TermHintDecoder {
  static func wordNgrams(
    _ input: WordNgramInput, _ out: inout [TaggedSpan], _ seen: inout Set<Int>
  ) {
    let localWidth = words(input.text, input.start, input.end)
    guard !localWidth.isEmpty else { return }
    if localWidth.count == 1 {
      appendTagged(input.text, localWidth[0], "word", &out, &seen)
    } else {
      for localInput in localWidth {
        appendTagged(input.text, localInput, "word", &out, &seen)
      }
      appendWordNgramSequences(input.text, localWidth, input.maxN, &out, &seen)
      appendTagged(input.text, (localWidth[1].0, localWidth.last!.1), "word", &out, &seen)
      appendTagged(
        input.text, (localWidth[0].0, localWidth[localWidth.count - 2].1), "word", &out, &seen)
    }
    appendWordNgramFragments(input.text, localWidth, &out, &seen)
  }

  private static func appendTagged(
    _ text: [Unicode.Scalar], _ span: (Int, Int), _ kind: String,
    _ out: inout [TaggedSpan], _ seen: inout Set<Int>
  ) {
    let key = span.0 * 1_000_000 + span.1
    guard seen.insert(key).inserted,
      !HintNorm.norm(sliceStr(text, span.0, span.1)).isEmpty else { return }
    out.append(TaggedSpan(start: span.0, end: span.1, kind: kind))
  }

  private static func appendWordNgramSequences(
    _ text: [Unicode.Scalar], _ widths: [(Int, Int)], _ maxN: Int,
    _ out: inout [TaggedSpan], _ seen: inout Set<Int>
  ) {
    for localCount in 2...min(maxN, widths.count) {
      for localLimit in 0...(widths.count - localCount) {
        var valid = true
        for localMiddle in 1..<localCount {
          let gap = text[
            widths[localLimit + localMiddle - 1].1..<widths[localLimit + localMiddle].0]
          if gap.isEmpty || !gap.allSatisfy({ isW($0) }) {
            valid = false
            break
          }
        }
        if valid {
          appendTagged(
            text,
            (widths[localLimit].0, widths[localLimit + localCount - 1].1),
            "ngram", &out, &seen)
        }
      }
    }
  }

  private static func appendWordNgramFragments(
    _ text: [Unicode.Scalar], _ widths: [(Int, Int)],
    _ out: inout [TaggedSpan], _ seen: inout Set<Int>
  ) {
    // v2: 단어 내부 추가 조각
    for (localInput, localOutput) in widths {
      let localString = text[localInput..<localOutput]
      // duphalf: 'LinearityLinearity' → 'Linearity'
      if localString.count >= 4 && localString.count % 2 == 0 {
        let localHeading = localString.count / 2
        if localString.prefix(localHeading) == localString.suffix(localHeading) {
          appendTagged(text, (localInput, localInput + localHeading), "duphalf", &out, &seen)
        }
      }
      // dotsplit: 'peak.Swing' → 'peak','Swing' ('.' 뒤 대문자/숫자/한글)
      var previous: Unicode.Scalar?
      var localIndex = localInput
      for localCandidate in localString {
        if previous == "." && isDotSplitStart(localCandidate) {
          if localIndex - 1 > localInput {
            appendTagged(text, (localInput, localIndex - 1), "dotsplit", &out, &seen)
          }
          if localIndex < localOutput {
            appendTagged(text, (localIndex, localOutput), "dotsplit", &out, &seen)
          }
        }
        previous = localCandidate
        localIndex += 1
      }
    }
  }

  private static func isDotSplitStart(_ candidate: Unicode.Scalar) -> Bool {
    candidate.properties.isUppercase || isN(candidate)
      || (0xac00...0xd7a3).contains(candidate.value)
  }

  static func koNgrams(
    _ text: [Unicode.Scalar], _ localStart: Int, _ localEnd: Int,
    _ out: inout [TaggedSpan], _ seen: inout Set<Int>
  ) {
    let runs = koreanRuns(text, start: localStart, end: localEnd)
    appendKoreanCharNgrams(text, runs, &out, &seen)
    appendKoreanSpaceJoins(text, runs, &out, &seen)
  }

  private static func koreanRuns(
    _ text: [Unicode.Scalar], start: Int, end: Int
  ) -> [(Int, Int)] {
    var segment: Int?
    var runs: [(Int, Int)] = []
    for localIndex in start...end {
      let valid: Bool
      if localIndex < end {
        let candidate = text[localIndex]
        let value = candidate.value
        valid = (0xac00...0xd7a3).contains(value) || isL(candidate) || isN(candidate)
          || candidate == "-"
      } else {
        valid = false
      }
      if valid && segment == nil { segment = localIndex }
      if let localStartValue = segment, !valid || localIndex == end {
        let localEndValue = valid ? localIndex + 1 : localIndex
        runs.append((localStartValue, localEndValue))
        segment = nil
      }
    }
    return runs
  }

  private static func appendKoreanCharNgrams(
    _ text: [Unicode.Scalar], _ runs: [(Int, Int)],
    _ out: inout [TaggedSpan], _ seen: inout Set<Int>
  ) {
    for run in runs {
      let runLength = run.1 - run.0
      guard runLength >= 2 else { continue }
      for localLength in 2...min(koCharngramHi, runLength) {
        for localLimit in 0...(runLength - localLength) {
          let span = (run.0 + localLimit, run.0 + localLimit + localLength)
          let key = span.0 * 1_000_000 + span.1
          guard !seen.contains(key) else { continue }
          let piece = sliceStr(text, span.0, span.1)
          guard !HintNorm.norm(piece).isEmpty else { continue }
          let hasHangul = piece.unicodeScalars.contains {
            (0xac00...0xd7a3).contains($0.value)
          }
          let hasTerm = piece.range(of: "[A-Z0-9\\-]", options: .regularExpression) != nil
          guard hasHangul || hasTerm else { continue }
          seen.insert(key)
          out.append(TaggedSpan(start: span.0, end: span.1, kind: "charngram"))
        }
      }
    }
  }

  private static func appendKoreanSpaceJoins(
    _ text: [Unicode.Scalar], _ runs: [(Int, Int)],
    _ out: inout [TaggedSpan], _ seen: inout Set<Int>
  ) {
    for localIndex in 1..<max(runs.count, 1) {
      let left = runs[localIndex - 1]
      let right = runs[localIndex]
      guard right.0 - left.1 == 1, text[left.1] == " " else { continue }
      for localLeftLength in 1...4 {
        for localRightLength in 1...6 {
          let start = left.1 - localLeftLength
          let end = right.0 + localRightLength
          guard start >= left.0, end <= right.1 else { continue }
          let key = start * 1_000_000 + end
          guard !seen.contains(key) else { continue }
          let piece = sliceStr(text, start, end)
          guard !HintNorm.norm(piece).isEmpty else { continue }
          let hasHangul = piece.unicodeScalars.contains { (0xac00...0xd7a3).contains($0.value) }
          guard hasHangul else {
            continue
          }
          seen.insert(key)
          out.append(TaggedSpan(start: start, end: end, kind: "kospjoin"))
        }
      }
    }
  }

  static func piecejoin(
    _ input: TagGenerationInput, _ buffer: inout TaggedSpanBuffer
  ) {
    let core = delimiterRuns(input.text, start: input.start, end: input.end)
    guard core.count >= 2 else { return }
    for localCount in [2, 3] {
      guard core.count >= localCount else { continue }
      appendPieceJoins(input, core: core, count: localCount, &buffer)
    }
  }

  private static func delimiterRuns(
    _ text: [Unicode.Scalar], start: Int, end: Int
  ) -> [(Int, Int)] {
    var core: [(Int, Int)] = []
    var localStart = start
    var localIndex = start
    while localIndex < end {
      if isDelimiter(text[localIndex]) {
        if localIndex > localStart { core.append((localStart, localIndex)) }
        var next = localIndex
        while next < end && isDelimiter(text[next]) { next += 1 }
        localStart = next
        localIndex = next
      } else {
        localIndex += 1
      }
    }
    if localStart < end { core.append((localStart, end)) }
    return core
  }

  private static func appendPieceJoins(
    _ input: TagGenerationInput, core: [(Int, Int)], count: Int,
    _ buffer: inout TaggedSpanBuffer
  ) {
    for localLimit in 0...(core.count - count) {
      let start = core[localLimit].0
      let end = core[localLimit + count - 1].1
      let inner = core.filter { $0.0 >= start && $0.1 <= end }
      guard inner.count == count else { continue }
      if let scorer = input.scorer,
        inner.map({ scorer($0.0, $0.1) }).min()! < pieceMin { continue }
      let key = start * 1_000_000 + end
      guard !HintNorm.norm(sliceStr(input.text, start, end)).isEmpty,
        buffer.seen.insert(key).inserted else { continue }
      buffer.spans.append(TaggedSpan(start: start, end: end, kind: "piecejoin"))
    }
  }
}
