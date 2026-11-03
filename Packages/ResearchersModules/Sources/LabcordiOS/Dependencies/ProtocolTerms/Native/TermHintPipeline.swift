import CoreML
// TermHintPipeline.swift — 공개 API 파사드: text → [TermHint]
// 배포 경로는 평가 sweep 기록이나 후보 캐시를 보유하지 않는다.
// 사용: let p = try TermHintPipeline(modelURL: spm, modelPackageURL: pkg, charVocabURL: vocab)
//       let hints = p.hints(for: text, language: "ko")
import Foundation

nonisolated private func makeArr(_ values: [Int], _ shape: [Int]) throws -> MLMultiArray {
  let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .int32)
  for (index, value) in values.enumerated() { array[index] = NSNumber(value: value) }
  return array
}

nonisolated private func makeFArr(_ values: [Float], _ shape: [Int]) throws -> MLMultiArray {
  let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
  for (index, value) in values.enumerated() { array[index] = NSNumber(value: value) }
  return array
}

nonisolated private struct TermHintModelWindowInput {
  let provider: MLFeatureProvider
  let unitCount: Int
}

nonisolated public final class TermHintPipeline {
  let tokenizer: MiniLMTokenizer
  let model: MLModel
  let charMap: [UInt32: Int]
  private let sectionPriority: SectionPriority?
  private let ranking: TermHintRanking

  public init(
    modelURL spm: URL, modelPackageURL pkg: URL, charVocabURL vocab: URL,
    knownTermsURL: URL? = nil,
    sectionPriorityRulesURL: URL? = nil,
    koreanRulesURL: URL? = nil,
    configuration: MLModelConfiguration = .init(),
    ranking: TermHintRanking = .nativeFusion
  ) throws {
    try Self.validateRanking(ranking, rulesURL: sectionPriorityRulesURL)
    self.ranking = ranking
    guard let localToken = MiniLMTokenizer(modelPath: spm.path) else {
      throw PreprocessError.checksum
    }
    tokenizer = localToken
    let compiled = try MLModel.compileModel(at: pkg)
    model = try MLModel(contentsOf: compiled, configuration: configuration)
    let localValueData = try Data(contentsOf: vocab)
    guard
      let localValueIndex = try JSONSerialization.jsonObject(with: localValueData)
        as? [String: Any]
    else { throw PreprocessError.checksum }
    var map = [UInt32: Int]()
    guard let characterValues = localValueIndex["characters"] as? [String] else {
      throw PreprocessError.checksum
    }
    for (localIndex, localCandidate) in characterValues.enumerated() {
      for localScore in localCandidate.unicodeScalars { map[localScore.value] = localIndex + 2 }
    }
    charMap = map
    if let rulesURL = sectionPriorityRulesURL {
      let rules = try JSONDecoder().decode(PriorityRules.self, from: Data(contentsOf: rulesURL))
      let korean = try koreanRulesURL.map {
        try JSONDecoder().decode(KoreanHeadingRules.self, from: Data(contentsOf: $0))
      }
      sectionPriority = try SectionPriority(rules: rules, koreanRules: korean)
    } else {
      sectionPriority = nil
    }
    TermHintDecoder.debugMerged = sectionPriority != nil
    if let kurl = knownTermsURL,
      let localKindData = try? Data(contentsOf: kurl),
      let localKindIndex = try? JSONSerialization.jsonObject(with: localKindData)
        as? [String: Any],
      let terms = localKindIndex["terms"] as? [String] {
      TermHintDecoder.knownTerms = Set(terms)
      if let localEnd = localKindIndex["bonus"] as? NSNumber {
        TermHintDecoder.knownBonus = localEnd.floatValue
      }
    }
  }

  private static func validateRanking(_ ranking: TermHintRanking, rulesURL: URL?) throws {
    guard ranking == .nativeFusion || rulesURL != nil else { throw RankingError.invalidSource }
  }

  private func predictOutputs(
    text: String, units: [(Int, Int)], windows: [TermPreprocessor.LedgerWindow],
    encoding: (ids: [Int], offsets: [(Int, Int)])
  ) -> [[[Float]]]? {
    var outputs: [[[Float]]] = []
    for localWidth in windows {
      guard !Task.isCancelled else { return nil }
      guard let rows = predictWindow(text, units: units, window: localWidth, encoding: encoding)
      else { return nil }
      outputs.append(rows)
    }
    return outputs
  }

  private func predictWindow(
    _ text: String, units: [(Int, Int)], window: TermPreprocessor.LedgerWindow,
    encoding: (ids: [Int], offsets: [(Int, Int)])
  ) -> [[Float]]? {
    let localUnit = window.unitIndices.count
    guard localUnit > 0 else { return [] }
    guard let modelInput = makeWindowInput(
      text, units: units, window: window, encoding: encoding) else { return nil }
    guard let output = try? model.prediction(from: modelInput.provider),
      let key = output.featureNames.first,
      let logits = output.featureValue(for: key)?.multiArrayValue,
      logits.count == modelInput.unitCount * 3 else { return nil }
    guard (0..<logits.count).allSatisfy({ logits[$0].floatValue.isFinite }) else { return nil }
    var rows = [[Float]](repeating: [0, 0, 0], count: modelInput.unitCount)
    for localNextIndex in 0..<modelInput.unitCount {
      for localLimit in 0..<3 {
        rows[localNextIndex][localLimit] =
          logits[localNextIndex * 3 + localLimit].floatValue
      }
    }
    return rows
  }

  private func makeWindowInput(
    _ text: String, units: [(Int, Int)], window: TermPreprocessor.LedgerWindow,
    encoding: (ids: [Int], offsets: [(Int, Int)])
  ) -> TermHintModelWindowInput? {
    let localUnit = window.unitIndices.count
    let cids = TermPreprocessor.charIds(
      text: text, unitOffsets: units, sel: window.unitIndices, charMap: charMap)
    let localMiddle = max(
      1,
      (1..<cids.unitCharOffsets.count).map {
        cids.unitCharOffsets[$0] - cids.unitCharOffsets[$0 - 1]
      }.max() ?? 1)
    guard localMiddle <= 64 else { return nil }
    var charFlat = [Int](repeating: 0, count: localUnit * localMiddle)
    var maskFlat = [Int](repeating: 0, count: localUnit * localMiddle)
    for localNextIndex in 0..<localUnit {
      let localStart = cids.unitCharOffsets[localNextIndex]
      let localEnd = cids.unitCharOffsets[localNextIndex + 1]
      for localLimit in localStart..<localEnd {
        let flatIndex = localNextIndex * localMiddle + (localLimit - localStart)
        charFlat[flatIndex] = cids.flat[localLimit]
        maskFlat[flatIndex] = 1
      }
    }
    var rel = [Float](repeating: 0, count: localUnit * 3)
    for localNextIndex in 0..<localUnit {
      rel[localNextIndex * 3] = Float(window.relStart[localNextIndex])
      rel[localNextIndex * 3 + 1] = Float(window.relEnd[localNextIndex])
      rel[localNextIndex * 3 + 2] = Float(window.mapped[localNextIndex])
    }
    let ids = window.flatIndices.enumerated().map { localPiece, localValue in
      localValue < 0 ? (localPiece == 0 ? 0 : 2) : encoding.ids[localValue]
    }
    guard let provider = try? MLDictionaryFeatureProvider(dictionary: [
      "ids": makeArr(ids, [1, window.flatIndices.count]),
      "attention_1": makeArr(
        Array(repeating: 1, count: window.flatIndices.count),
        [1, window.flatIndices.count]),
      "char_ids": makeArr(charFlat, [1, localUnit, localMiddle]),
      "char_mask": makeArr(maskFlat, [1, localUnit, localMiddle]),
      "token_indices": makeArr(window.tokenIndices, [1, localUnit]),
      "relative": makeFArr(rel, [1, localUnit, 3])
    ]) else { return nil }
    return TermHintModelWindowInput(provider: provider, unitCount: localUnit)
  }

  /// 문서 텍스트 → STT contextual hints (≤ K개, 방출 우선순위).
  /// 빈 입력·0 이하 K 또는 추론 실패는 빈 배열을 반환한다. 부분 문서 힌트는 반환하지 않는다.
  public func hints(for text: String, language: String, K termLimit: Int = 100) -> [TermHint] {
    if TermHintDecoder.debugMerged { TermHintDecoder.lastMerged = [] }
    guard termLimit > 0, !text.isEmpty else { return [] }
    let enc = tokenizer.encode(text)
    guard let localSourceUnit = try? TermPreprocessor.safeUnits(text) else { return [] }
    let ledger = TermPreprocessor.buildLedger(
      text: text, unitOffsets: localSourceUnit.offsets, unsafe: localSourceUnit.unsafe,
      rawOffsets: enc.offsets, flatIds: enc.ids, step: 446)
    let wins = ledger.windows
    guard let outputs = predictOutputs(
      text: text, units: localSourceUnit.offsets, windows: wins, encoding: enc) else { return [] }
    let merged = TermPreprocessor.mergeUnitLogits(
      windowCount: wins.count,
      units: localSourceUnit.offsets.count, windows: wins, outputs: outputs
    )
    .map { $0.map { Float($0) } }
    let baseline = TermHintDecoder.extract(
      text, logits: merged, unitOffsets: localSourceUnit.offsets,
      lang: language, termLimit: termLimit, tau: nil)
    guard let sectionPriority else { return baseline }

    // The frozen evaluation applied the same admission policy before the
    // native section-priority reciprocal-rank fusion. Keeping this as an
    // opt-in initializer argument preserves the plain extraction API.
    let chars = Array(text.unicodeScalars)
    let cached = TermHintDecoder.lastMerged.compactMap { candidate -> CachedCandidate? in
      let start = candidate.start
      let end = candidate.end
      let score = candidate.score
      let noFilter = candidate.noFilter
      guard start >= 0, end > start, end <= chars.count, score.isFinite else { return nil }
      let norm = HintNorm.norm(TermHintDecoder.sliceStr(chars, start, end))
      let decision = AdmissionDecision.decide(AdmissionInput(
        chars: chars, language: language, start: start, end: end,
        score: score, noFilter: noFilter, norm: norm))
      return CachedCandidate(
        start: start, end: end, score: Double(score),
        admitted: decision.admitted, norm: norm)
    }
    guard let fused = try? rankedHints(
      cached, text: text, limit: termLimit, priority: sectionPriority) else { return baseline }
    return fused.map {
      TermHint(text: $0.text, start: $0.start, end: $0.end, score: Float($0.score))
    }
  }

  private func rankedHints(
    _ candidates: [CachedCandidate], text: String, limit: Int, priority: SectionPriority
  ) throws -> [RankingHint] {
    let (ranges, _) = priority.ranges(in: text)
    let fusionLimit = ranking == .guardedFrequency ? max(limit, 100) : limit
    let fusion = try priority.emitFusion(
      candidates, text: text, localLimit: fusionLimit, ranges: ranges)
    if ranking == .guardedFrequency {
      return try DocumentFrequencyRanking.hints(
        candidates: candidates, fusion: fusion, text: text, limit: limit)
    }
    return fusion
  }

  /// SFSpeechRecognitionContextualStrings/ customWords 주입용 표면 문자열
  public func hintStrings(for text: String, language: String, K termLimit: Int = 100) -> [String] {
    hints(for: text, language: language, K: termLimit).map { $0.text }
  }
}
