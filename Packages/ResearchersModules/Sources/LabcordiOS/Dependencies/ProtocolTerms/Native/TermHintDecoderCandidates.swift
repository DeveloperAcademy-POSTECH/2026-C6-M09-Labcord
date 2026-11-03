import Foundation

nonisolated extension TermHintDecoder {
  /// 후보 표면을 정제 조각열로 분해: (x,y,weak)
  /// 분할점: 공백, '.', '\u{00b7}', '/', EN lower->Upper 융합 경계
  static func cleanPieces(
    _ chars: [Unicode.Scalar], _ localStart: Int, _ localEnd: Int, _ lang: String
  ) -> [CleanPiece] {
    var raw: [CleanPiece] = []
    for (localWx, localWy) in words(chars, localStart, localEnd) {
      var cuts = [localWx]
      var splitAt = Set<Int>()
      var localIndex = localWx
      while localIndex < localWy {
        let localCandidate = chars[localIndex]
        let nxt: Unicode.Scalar? = localIndex + 1 < localWy ? chars[localIndex + 1] : nil
        if localCandidate == "." || localCandidate == "\u{00b7}" || localCandidate == "/" {
          if localIndex > localWx { cuts.append(localIndex) }
          cuts.append(localIndex + 1)
          splitAt.insert(localIndex + 1)
        } else if lang != "ko", localCandidate.properties.isLowercase, let localCount = nxt,
          localCount.properties.isUppercase {
          cuts.append(localIndex + 1)
          splitAt.insert(localIndex + 1)
        }
        localIndex += 1
      }
      cuts.append(localWy)
      for localNextIndex in 0..<cuts.count - 1 {
        let localString = cuts[localNextIndex]
        let localEndValue = cuts[localNextIndex + 1]
        if localString < localEndValue {
          raw.append(
            CleanPiece(
              start: localString, end: localEndValue, weak: splitAt.contains(localString)))
        }
      }
    }
    var out: [CleanPiece] = []
    for localPiece in raw {
      var localString = localPiece.start
      var localEndValue = localPiece.end
      while localString < localEndValue && !isL(chars[localString]) && !isN(chars[localString]) {
        localString += 1
      }
      while localEndValue > localString && !isL(chars[localEndValue - 1])
        && !isN(chars[localEndValue - 1]) { localEndValue -= 1 }
      out.append(CleanPiece(start: localString, end: localEndValue, weak: localPiece.weak))
    }
    return out
  }

  /// 정제 토큰열 기반 파생 스팬
  static func cleanVariants(
    _ chars: [Unicode.Scalar], _ localStart: Int, _ localEnd: Int, _ lang: String
  ) -> [(
    Int, Int
  )] {
    let pieces = cleanPieces(chars, localStart, localEnd, lang)
    if pieces.isEmpty { return [] }
    var seq: [(Int, Int)] = []
    var hard = Set<Int>()
    for localPiece in pieces {
      let localString = localPiece.start
      let localEndValue = localPiece.end
      if localString >= localEndValue { continue }
      let frag = sliceStr(chars, localString, localEndValue)
      // 미닫힘 '(' → 이후 전부 drop
      if frag.contains("(") && !frag.contains(")") {
        if !seq.isEmpty { hard.insert(seq.count - 1) }
        break
      }
      // '.'/'\u{00b7}'/'/' 결합 순수숫자, 전 조각이 숫자가 아니면 각주 drop
      if frag.allSatisfy(\.isNumber), let (localPositions, localPe) = seq.last,
        localString - localPe == 1, [".", "\u{00b7}", "/"].contains(chars[localPe]),
        !sliceStr(chars, localPositions, localPe).allSatisfy(\.isNumber) {
        hard.insert(seq.count - 1)
        continue
      }
      if localPiece.weak && !seq.isEmpty { hard.insert(seq.count - 1) }
      seq.append((localString, localEndValue))
    }
    if seq.isEmpty { return [] }
    hard.insert(seq.count - 1)
    var spans: [(Int, Int)] = []
    for end in hard.sorted() {
      var localLimit = max(0, end - 7)
      while localLimit <= end {
        spans.append((seq[localLimit].0, seq[end].1))
        localLimit += 1
      }
    }
    return spans
  }

  static func genTagged(_ input: TagGenerationInput) -> [TaggedSpan] {
    var buffer = TaggedSpanBuffer()
    var stack = [TaggedWorkItem(start: input.start, end: input.end, depth: 0)]
    while let work = stack.popLast() {
      appendTaggedRoot(input, work: work, buffer: &buffer)
      if work.depth < input.depth {
        appendTaggedChildren(input.text, work: work, stack: &stack)
      }
      wordNgrams(
        WordNgramInput(text: input.text, start: work.start, end: work.end, maxN: input.maxN),
        &buffer.spans, &buffer.seen)
      piecejoin(
        TagGenerationInput(
          text: input.text, start: work.start, end: work.end, language: input.language,
          maxN: input.maxN, depth: input.depth, emitRoot: input.emitRoot, scorer: input.scorer),
        &buffer)
    }
    if input.language == "ko" {
      appendKoreanTagged(input, buffer: &buffer)
    }
    return buffer.spans
  }

  private static func appendTaggedRoot(
    _ input: TagGenerationInput, work: TaggedWorkItem, buffer: inout TaggedSpanBuffer
  ) {
    guard work.end - work.start >= 1 else { return }
    let key = work.start * 1_000_000 + work.end
    guard input.emitRoot || (work.start, work.end) != (input.start, input.end),
      buffer.seen.insert(key).inserted,
      !HintNorm.norm(sliceStr(input.text, work.start, work.end)).isEmpty else { return }
    buffer.spans.append(TaggedSpan(start: work.start, end: work.end, kind: "delim"))
  }

  private static func appendTaggedChildren(
    _ text: [Unicode.Scalar], work: TaggedWorkItem, stack: inout [TaggedWorkItem]
  ) {
    var localP0 = work.start
    var found = false
    var localIndex = work.start
    while localIndex < work.end {
      if isDelimiter(text[localIndex]) {
        found = true
        if localIndex > localP0 {
          stack.append(
            TaggedWorkItem(start: localP0, end: localIndex, depth: work.depth + 1))
        }
        var localNextIndex = localIndex
        while localNextIndex < work.end && isDelimiter(text[localNextIndex]) {
          localNextIndex += 1
        }
        localP0 = localNextIndex
        localIndex = localNextIndex
      } else {
        localIndex += 1
      }
    }
    if found && localP0 < work.end {
      stack.append(TaggedWorkItem(start: localP0, end: work.end, depth: work.depth + 1))
    }
  }

  private static func appendKoreanTagged(
    _ input: TagGenerationInput, buffer: inout TaggedSpanBuffer
  ) {
    let sub = Array(input.text[input.start..<input.end])
    for particle in innerParticles {
      appendKoreanParticle(
        input, sub: sub, particle: Array(particle.unicodeScalars), buffer: &buffer)
    }
    koNgrams(input.text, input.start, input.end, &buffer.spans, &buffer.seen)
  }

  private static func appendKoreanParticle(
    _ input: TagGenerationInput, sub: [Unicode.Scalar], particle: [Unicode.Scalar],
    buffer: inout TaggedSpanBuffer
  ) {
    var start = min(1, sub.count)
    while start < sub.count {
      guard let found = findKoreanParticle(sub, particle, from: start) else { break }
      appendKoreanParticleSpans(
        input, sub: sub, particle: particle, index: found, buffer: &buffer)
      start = found + particle.count
    }
  }

  private static func findKoreanParticle(
    _ sub: [Unicode.Scalar], _ particle: [Unicode.Scalar], from start: Int
  ) -> Int? {
    var localIndex = start
    while localIndex + particle.count <= sub.count {
      var match = true
      for localLimit in 0..<particle.count
      where sub[localIndex + localLimit] != particle[localLimit] {
        match = false
        break
      }
      if match { return localIndex }
      localIndex += 1
    }
    return nil
  }

  private static func appendKoreanParticleSpans(
    _ input: TagGenerationInput, sub: [Unicode.Scalar], particle: [Unicode.Scalar],
    index: Int, buffer: inout TaggedSpanBuffer
  ) {
    let localIndex = index
    if localIndex >= 2 {
      appendTaggedSpan(
        input.text, (input.start, input.start + localIndex), "ko_inner", buffer: &buffer)
    }
    let remainder = localIndex + particle.count
    if remainder < sub.count,
      appendTaggedSpan(
        input.text, (input.start + remainder, input.end), "ko_inner", buffer: &buffer) {
      wordNgrams(
        WordNgramInput(
          text: input.text, start: input.start + remainder, end: input.end, maxN: 3),
        &buffer.spans, &buffer.seen)
    }
  }

  @discardableResult
  private static func appendTaggedSpan(
    _ text: [Unicode.Scalar], _ span: (Int, Int), _ kind: String,
    buffer: inout TaggedSpanBuffer
  ) -> Bool {
    guard !HintNorm.norm(sliceStr(text, span.0, span.1)).isEmpty else { return false }
    let key = span.0 * 1_000_000 + span.1
    guard buffer.seen.insert(key).inserted else { return false }
    buffer.spans.append(TaggedSpan(start: span.0, end: span.1, kind: kind))
    return true
  }
}
