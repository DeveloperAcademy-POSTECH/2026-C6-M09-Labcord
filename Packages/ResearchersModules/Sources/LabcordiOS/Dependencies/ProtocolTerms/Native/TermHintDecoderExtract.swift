import Foundation

nonisolated extension TermHintDecoder {
  nonisolated(unsafe) public static var scoreMode: String = "mean"  // mean | topHalf
  // 0은 무제한입니다. 양수이면 일반 긴 n-그램의 단어 수를 제한합니다.
  nonisolated(unsafe) public static var maxWords: Int = 0

  public static func extract(
    _ text: String, logits: [[Float]], unitOffsets: [(Int, Int)], lang: String,
    termLimit: Int = 100,
    tau: Float? = nil
  ) -> [TermHint] {
    if debugMerged { lastMerged = [] }
    let chars = Array(text.unicodeScalars)
    guard termLimit > 0, !chars.isEmpty, !logits.isEmpty,
      logits.count == unitOffsets.count,
      logits.allSatisfy({ $0.count == 3 && $0.allSatisfy({ $0.isFinite }) }),
      unitOffsets.allSatisfy({ $0.0 >= 0 && $0.1 > $0.0 && $0.1 <= chars.count })
    else { return [] }
    let token = tau ?? (defaultTau[lang] ?? 0.012)
    let probs = calcProbs(logits)
    let ordered = unitOffsets.indices.dropFirst().allSatisfy {
      unitOffsets[$0 - 1].1 <= unitOffsets[$0].0
    }
    let scorer = CandidateScoreComputer(
      probs: probs, unitOffsets: unitOffsets, orderedOffsets: ordered)
    let input = ExtractionInput(
      text: text, chars: chars, logits: logits, probs: probs, unitOffsets: unitOffsets,
      language: lang, termLimit: termLimit, token: token, scorer: scorer)
    return extractValidated(input)
  }

  private static func extractValidated(_ input: ExtractionInput) -> [TermHint] {
    let pools = poolSpans(input)
    let docWords = words(input.chars, 0, input.chars.count)
    var candidates: [CandidateRecord] = []
    var regions: [GeneratedRegion] = []
    appendPoolCandidates(input, pools, docWords, &candidates, &regions)
    appendBridgeCandidates(pools, &candidates, &regions)
    appendTaggedCandidates(input, regions, &candidates)
    appendPathCandidates(input, &candidates)
    applyKnownBonus(input.chars, &candidates)
    let clean = cleanVariantSpans(input, candidates)
    let oligos = oligoSpans(input)
    let merged = mergeCandidates(candidates, clean, oligos)
    return emitHints(input, merged)
  }

  private static func poolSpans(_ input: ExtractionInput) -> [ScoredSpan] {
    var spans: [ScoredSpan] = []
    var current: [Int] = []
    for (localIndex, localPiece) in input.probs.enumerated() {
      if localPiece >= input.token {
        current.append(localIndex)
      } else if !current.isEmpty {
        spans.append(scoredPool(current, input))
        current = []
      }
    }
    if !current.isEmpty { spans.append(scoredPool(current, input)) }
    return spans
  }

  private static func scoredPool(_ indices: [Int], _ input: ExtractionInput) -> ScoredSpan {
    ScoredSpan(
      start: input.unitOffsets[indices[0]].0,
      end: input.unitOffsets[indices.last!].1,
      score: indices.map { input.probs[$0] }.reduce(0, +) / Float(indices.count))
  }

  private static func appendPoolCandidates(
    _ input: ExtractionInput, _ pools: [ScoredSpan], _ docWords: [(Int, Int)],
    _ candidates: inout [CandidateRecord], _ regions: inout [GeneratedRegion]
  ) {
    for pool in pools {
      appendPoolExtras(input, pool, docWords, &candidates, &regions)
    }
  }

  private static func appendPoolExtras(
    _ input: ExtractionInput, _ pool: ScoredSpan, _ docWords: [(Int, Int)],
    _ candidates: inout [CandidateRecord], _ regions: inout [GeneratedRegion]
  ) {
    let localStart = pool.start
    let localEnd = pool.end
    candidates.append(
      CandidateRecord(
        start: localStart, end: localEnd, score: pool.score * genPenalty["pool"]!,
        tierTwo: false, noFilter: false, kind: "pool"))
    regions.append(GeneratedRegion(start: localStart, end: localEnd, emitRoot: true))
    var localNa = localStart
    var localNb = localEnd
    for (localInput, localOutput) in docWords {
      if localInput < localNa && localOutput > localNa && localOutput - localNa <= 6 {
        localNa = localInput
      }
      if localInput < localNb && localOutput > localNb && localNb - localInput <= 6 {
        localNb = localInput
      }
      if localInput <= localStart && localOutput >= localEnd {
        localNa = localInput
        localNb = localOutput
      }
    }
    if (localNa, localNb) != (localStart, localEnd) && localNa < localNb {
      candidates.append(
        CandidateRecord(
          start: localNa, end: localNb,
          score: input.scorer.score(localNa, localNb, mode: scoreMode) * genPenalty["wsnap"]!,
          tierTwo: true, noFilter: false, kind: "wsnap"))
      regions.append(GeneratedRegion(start: localNa, end: localNb, emitRoot: false))
    }
    let previous = docWords.last {
      $0.1 <= localStart && $0.1 < localStart
        && input.chars[$0.1..<localStart].allSatisfy { isW($0) }
    }
    let next = docWords.first {
      $0.0 >= localEnd && $0.0 > localEnd
        && input.chars[localEnd..<$0.0].allSatisfy { isW($0) }
    }
    appendExtensionCandidates(
      input, ExtensionCandidates(start: localStart, end: localEnd, previous: previous, next: next),
      &candidates)
  }

  private static func appendExtensionCandidates(
    _ input: ExtractionInput, _ values: ExtensionCandidates,
    _ candidates: inout [CandidateRecord]
  ) {
    if let previous = values.previous {
      candidates.append(
        CandidateRecord(
          start: previous.0, end: values.end,
          score: input.scorer.score(previous.0, values.end, mode: scoreMode) * genPenalty["ext"]!,
          tierTwo: false, noFilter: false, kind: "ext"))
    }
    if let next = values.next {
      candidates.append(
        CandidateRecord(
          start: values.start, end: next.1,
          score: input.scorer.score(values.start, next.1, mode: scoreMode) * genPenalty["ext"]!,
          tierTwo: false, noFilter: false, kind: "ext"))
    }
    if let previous = values.previous, let next = values.next {
      candidates.append(
        CandidateRecord(
          start: previous.0, end: next.1,
          score: input.scorer.score(previous.0, next.1, mode: scoreMode) * genPenalty["ext"]!,
          tierTwo: false, noFilter: false, kind: "ext"))
    }
  }

  private static func appendBridgeCandidates(
    _ pools: [ScoredSpan], _ candidates: inout [CandidateRecord],
    _ regions: inout [GeneratedRegion]
  ) {
    for localIndex in 1..<max(pools.count, 1) {
      let left = pools[localIndex - 1]
      let right = pools[localIndex]
      let gap = right.start - left.end
      guard gap >= 0, gap <= bridgeGap else { continue }
      candidates.append(
        CandidateRecord(
          start: left.start, end: right.end,
          score: min(left.score, right.score) * 0.9,
          tierTwo: true, noFilter: false, kind: "pooljoin"))
      regions.append(GeneratedRegion(start: left.start, end: right.end, emitRoot: false))
    }
  }

  private static func appendTaggedCandidates(
    _ input: ExtractionInput, _ regions: [GeneratedRegion],
    _ candidates: inout [CandidateRecord]
  ) {
    let newKinds: Set<String> = ["wsnap", "piecejoin", "dotsplit", "duphalf", "kospjoin"]
    for region in regions {
      let generation = TagGenerationInput(
        text: input.chars, start: region.start, end: region.end,
        language: input.language, maxN: 5, depth: 3, emitRoot: region.emitRoot,
      ) { input.scorer.score($0, $1, mode: scoreMode) }
      for tagged in genTagged(generation) {
        candidates.append(
          CandidateRecord(
            start: tagged.start, end: tagged.end,
            score: input.scorer.score(tagged.start, tagged.end, mode: scoreMode)
              * genPenalty[tagged.kind]!,
            tierTwo: !region.emitRoot || newKinds.contains(tagged.kind),
            noFilter: noFilterKinds.contains(tagged.kind), kind: tagged.kind))
      }
    }
  }

  private static func appendPathCandidates(
    _ input: ExtractionInput, _ candidates: inout [CandidateRecord]
  ) {
    let labels = viterbi(input.logits)
    var current: Int?
    for (localIndex, label) in labels.enumerated() {
      if label == 1 || label == 2 {
        if current == nil { current = localIndex }
      } else if let startIndex = current {
        appendPathCandidate(input, startIndex, localIndex - 1, &candidates)
        current = nil
      }
    }
    if let startIndex = current {
      appendPathCandidate(input, startIndex, labels.count - 1, &candidates)
    }
  }

  private static func appendPathCandidate(
    _ input: ExtractionInput, _ startIndex: Int, _ endIndex: Int,
    _ candidates: inout [CandidateRecord]
  ) {
    let localStart = input.unitOffsets[startIndex].0
    let localEnd = input.unitOffsets[endIndex].1
    candidates.append(
      CandidateRecord(
        start: localStart, end: localEnd,
        score: 1.0 + input.scorer.score(localStart, localEnd, mode: scoreMode),
        tierTwo: false, noFilter: false, kind: "path"))
  }

  private static func applyKnownBonus(
    _ chars: [Unicode.Scalar], _ candidates: inout [CandidateRecord]
  ) {
    guard let known = TermHintDecoder.knownTerms else { return }
    candidates = candidates.map { candidate in
      guard known.contains(HintNorm.norm(sliceStr(chars, candidate.start, candidate.end)))
      else { return candidate }
      return CandidateRecord(
        start: candidate.start, end: candidate.end,
        score: candidate.score * TermHintDecoder.knownBonus,
        tierTwo: candidate.tierTwo, noFilter: candidate.noFilter, kind: candidate.kind)
    }
  }

  private static func cleanVariantSpans(
    _ input: ExtractionInput, _ candidates: [CandidateRecord]
  ) -> [ScoredSpan] {
    var variants: [ScoredSpan] = []
    for candidate in candidates {
      for localVariant in cleanVariants(
        input.chars, candidate.start, candidate.end, input.language)
      where localVariant.0 != candidate.start || localVariant.1 != candidate.end {
        variants.append(
          ScoredSpan(
            start: localVariant.0, end: localVariant.1,
            score: candidate.score * cleanVarPenalty))
      }
    }
    return variants
  }

  private static func oligoSpans(_ input: ExtractionInput) -> [ScoredSpan] {
    var oligos: [ScoredSpan] = []
    let fullRange = NSRange(location: 0, length: (input.text as NSString).length)
    for match in oligoPattern.matches(in: input.text, range: fullRange) {
      guard let result = Range(match.range, in: input.text) else { continue }
      let start = input.text.unicodeScalars.distance(
        from: input.text.unicodeScalars.startIndex, to: result.lowerBound)
      let end = input.text.unicodeScalars.distance(
        from: input.text.unicodeScalars.startIndex, to: result.upperBound)
      oligos.append(ScoredSpan(start: start, end: end, score: oligoScore))
    }
    return oligos
  }

  private static func stableRecords(_ records: [CandidateRecord]) -> [CandidateRecord] {
    records.enumerated().sorted {
      $0.1.score > $1.1.score || ($0.1.score == $1.1.score && $0.0 < $1.0)
    }.map { $0.1 }
  }

  private static func mergedRecords(
    _ records: [CandidateRecord], tier: Int
  ) -> [MergedCandidate] {
    records.map {
      MergedCandidate(
        start: $0.start, end: $0.end, score: $0.score,
        tierTwo: $0.tierTwo, noFilter: $0.noFilter, kind: $0.kind, tier: tier)
    }
  }

  private static func mergeCandidates(
    _ candidates: [CandidateRecord], _ clean: [ScoredSpan], _ oligos: [ScoredSpan]
  ) -> [MergedCandidate] {
    let first = stableRecords(candidates.filter { !$0.tierTwo })
    let second = stableRecords(candidates.filter { $0.tierTwo })
    let cleanRecords = clean.map {
      CandidateRecord(
        start: $0.start, end: $0.end, score: $0.score,
        tierTwo: true, noFilter: true, kind: "cleanvar")
    }
    let oligoRecords = oligos.map {
      CandidateRecord(
        start: $0.start, end: $0.end, score: $0.score,
        tierTwo: true, noFilter: true, kind: "oligo")
    }
    return mergedRecords(first, tier: 1) + mergedRecords(stableRecords(oligoRecords), tier: 1)
      + mergedRecords(second, tier: 2) + mergedRecords(stableRecords(cleanRecords), tier: 3)
  }

  private static func emitHints(
    _ input: ExtractionInput, _ merged: [MergedCandidate]
  ) -> [TermHint] {
    if TermHintDecoder.debugMerged { TermHintDecoder.lastMerged = merged }
    var seen = Set<String>()
    var output: [TermHint] = []
    for candidate in merged {
      let localString = sliceStr(input.chars, candidate.start, candidate.end)
      let normalized = HintNorm.norm(localString)
      guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
      let decision = AdmissionDecision.decide(AdmissionInput(
        chars: input.chars, language: input.language, start: candidate.start, end: candidate.end,
        score: candidate.score, noFilter: candidate.noFilter, norm: normalized))
      guard decision.admitted else { continue }
      seen.insert(normalized)
      let wordCount = localString.split { $0.isWhitespace }.count
      if maxWords > 0 && wordCount > maxWords {
        let technical = localString.contains { $0.isNumber || $0 == "-" || $0.isUppercase }
        if !technical { continue }
      }
      output.append(
        TermHint(
          text: localString, start: candidate.start, end: candidate.end, score: candidate.score))
      if output.count >= input.termLimit { break }
    }
    return output
  }
}
