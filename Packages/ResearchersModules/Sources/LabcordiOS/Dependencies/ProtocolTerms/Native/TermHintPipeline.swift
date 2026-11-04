import CoreML
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
  public init(
    modelURL spm: URL, modelPackageURL pkg: URL, charVocabURL vocab: URL,
    configuration: MLModelConfiguration = .init()
  ) throws {
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

  /// 모델 BIO 경계 그대로 원문 scalar span을 반환합니다. 규칙 확장·트림은 하지 않습니다.
  public func hints(for text: String) throws -> [TermHint] {
    try Task.checkCancellation()
    guard !text.isEmpty else { return [] }
    let encoding = tokenizer.encode(text)
    let units = try TermPreprocessor.safeUnits(text)
    let ledger = TermPreprocessor.buildLedger(
      text: text, unitOffsets: units.offsets, unsafe: units.unsafe,
      rawOffsets: encoding.offsets, flatIds: encoding.ids, step: 446)
    var covered = Set<Int>()
    for window in ledger.windows {
      for (index, unit) in window.unitIndices.enumerated() where window.coreMask[index] {
        covered.insert(unit)
      }
    }
    guard covered.count == units.offsets.count else { throw R117NativeError.invalidPrediction }
    try Task.checkCancellation()
    let outputs = predictOutputs(
      text: text, units: units.offsets, windows: ledger.windows, encoding: encoding)
    try Task.checkCancellation()
    guard let outputs else { throw R117NativeError.invalidPrediction }
    let logits = TermPreprocessor.mergeUnitLogits(
      windowCount: ledger.windows.count, units: units.offsets.count,
      windows: ledger.windows, outputs: outputs).map { $0.map { Float($0) } }
    return try NativeBIODecoder.decode(text: text, logits: logits, offsets: units.offsets)
  }
}
