import CoreML
import Foundation

nonisolated private func makeIntegerTensor(
  _ values: [Int], _ shape: [Int]
) throws -> MLMultiArray {
  let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .int32)
  for (index, value) in values.enumerated() { array[index] = NSNumber(value: value) }
  return array
}

nonisolated private func makeFloatTensor(
  _ values: [Float], _ shape: [Int]
) throws -> MLMultiArray {
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
  let characterIDsByScalar: [UInt32: Int]
  public init(
    modelURL tokenizerModelURL: URL, modelPackageURL coreMLPackageURL: URL,
    charVocabURL characterVocabularyURL: URL,
    configuration: MLModelConfiguration = .init()
  ) throws {
    guard let loadedTokenizer = MiniLMTokenizer(modelPath: tokenizerModelURL.path) else {
      throw NativeTermError.tokenizerLoadFailed
    }
    tokenizer = loadedTokenizer
    let compiledModelURL = try MLModel.compileModel(at: coreMLPackageURL)
    model = try MLModel(contentsOf: compiledModelURL, configuration: configuration)
    let vocabularyData = try Data(contentsOf: characterVocabularyURL)
    guard
      let vocabularyObject = try JSONSerialization.jsonObject(with: vocabularyData)
        as? [String: Any]
    else { throw NativeTermError.invalidCharacterVocabulary }
    var map = [UInt32: Int]()
    guard let characterValues = vocabularyObject["characters"] as? [String] else {
      throw NativeTermError.invalidCharacterVocabulary
    }
    for (characterIndex, character) in characterValues.enumerated() {
      for scalar in character.unicodeScalars { map[scalar.value] = characterIndex + 2 }
    }
    characterIDsByScalar = map
  }

  private func predictOutputs(
    text: String, units: [(Int, Int)], windows: [TermPreprocessor.LedgerWindow],
    encoding: (tokenIDs: [Int], offsets: [(Int, Int)])
  ) throws -> [[[Float]]] {
    var outputs: [[[Float]]] = []
    for window in windows {
      try Task.checkCancellation()
      let rows = try predictWindow(text, units: units, window: window, encoding: encoding)
      outputs.append(rows)
    }
    return outputs
  }

  private func predictWindow(
    _ text: String, units: [(Int, Int)], window: TermPreprocessor.LedgerWindow,
    encoding: (tokenIDs: [Int], offsets: [(Int, Int)])
  ) throws -> [[Float]] {
    let unitCount = window.unitIndices.count
    guard unitCount > 0 else { return [] }
    let modelInput = try makeWindowInput(
      text, units: units, window: window, encoding: encoding)
    try Task.checkCancellation()
    let output: MLFeatureProvider
    do {
      output = try model.prediction(from: modelInput.provider)
    } catch {
      try Task.checkCancellation()
      throw error
    }
    try Task.checkCancellation()
    guard let key = output.featureNames.first,
      let logits = output.featureValue(for: key)?.multiArrayValue,
      logits.count == modelInput.unitCount * 3 else { throw NativeTermError.invalidPrediction }
    guard (0..<logits.count).allSatisfy({ logits[$0].floatValue.isFinite }) else {
      throw NativeTermError.invalidPrediction
    }
    var rows = [[Float]](repeating: [0, 0, 0], count: modelInput.unitCount)
    for unitIndex in 0..<modelInput.unitCount {
      for featureIndex in 0..<3 {
        rows[unitIndex][featureIndex] =
          logits[unitIndex * 3 + featureIndex].floatValue
      }
    }
    return rows
  }

  private func makeWindowInput(
    _ text: String, units: [(Int, Int)], window: TermPreprocessor.LedgerWindow,
    encoding: (tokenIDs: [Int], offsets: [(Int, Int)])
  ) throws -> TermHintModelWindowInput {
    let unitCount = window.unitIndices.count
    let characterEncoding = TermPreprocessor.characterIDs(
      text: text, unitOffsets: units, selectedUnitIndices: window.unitIndices,
      characterIDsByScalar: characterIDsByScalar)
    let maximumCharactersPerUnit = max(
      1,
      (1..<characterEncoding.unitCharacterOffsets.count).map {
        characterEncoding.unitCharacterOffsets[$0] - characterEncoding.unitCharacterOffsets[$0 - 1]
      }.max() ?? 1)
    guard maximumCharactersPerUnit <= 64 else { throw NativeTermError.invalidPrediction }
    var characterIDTensorValues = [Int](repeating: 0, count: unitCount * maximumCharactersPerUnit)
    var characterMaskTensorValues = [Int](
      repeating: 0, count: unitCount * maximumCharactersPerUnit)
    for unitIndex in 0..<unitCount {
      let characterStartIndex = characterEncoding.unitCharacterOffsets[unitIndex]
      let characterEndIndex = characterEncoding.unitCharacterOffsets[unitIndex + 1]
      for featureIndex in characterStartIndex..<characterEndIndex {
        let flatIndex = unitIndex * maximumCharactersPerUnit + (featureIndex - characterStartIndex)
        characterIDTensorValues[flatIndex] = characterEncoding.flat[featureIndex]
        characterMaskTensorValues[flatIndex] = 1
      }
    }
    var relativePositionTensorValues = [Float](repeating: 0, count: unitCount * 3)
    for unitIndex in 0..<unitCount {
      relativePositionTensorValues[unitIndex * 3] = Float(window.relativeStarts[unitIndex])
      relativePositionTensorValues[unitIndex * 3 + 1] = Float(window.relativeEnds[unitIndex])
      relativePositionTensorValues[unitIndex * 3 + 2] = Float(window.mapped[unitIndex])
    }
    let tokenIDs = window.sourceTokenIndices.enumerated().map { tokenPosition, sourceTokenIndex in
      sourceTokenIndex < 0 ? (tokenPosition == 0 ? 0 : 2) : encoding.tokenIDs[sourceTokenIndex]
    }
    let provider = try MLDictionaryFeatureProvider(dictionary: [
      "ids": makeIntegerTensor(tokenIDs, [1, window.sourceTokenIndices.count]),
      "attention_1": makeIntegerTensor(
        Array(repeating: 1, count: window.sourceTokenIndices.count),
        [1, window.sourceTokenIndices.count]),
      "char_ids": makeIntegerTensor(
        characterIDTensorValues, [1, unitCount, maximumCharactersPerUnit]),
      "char_mask": makeIntegerTensor(
        characterMaskTensorValues, [1, unitCount, maximumCharactersPerUnit]),
      "token_indices": makeIntegerTensor(window.tokenIndices, [1, unitCount]),
      "relative": makeFloatTensor(relativePositionTensorValues, [1, unitCount, 3])
    ])
    return TermHintModelWindowInput(provider: provider, unitCount: unitCount)
  }

  public func hints(for text: String) throws -> [TermHint] {
    try Task.checkCancellation()
    guard !text.isEmpty else { return [] }
    let encoding = tokenizer.encode(text)
    let units = try TermPreprocessor.safeUnits(text)
    let ledger = TermPreprocessor.buildLedger(
      text: text, unitOffsets: units.offsets, unsafe: units.unsafe,
      rawOffsets: encoding.offsets, tokenIDs: encoding.tokenIDs, windowStride: 446)
    var coveredUnitIndices = Set<Int>()
    for window in ledger.windows {
      for (index, unit) in window.unitIndices.enumerated() where window.coreMask[index] {
        coveredUnitIndices.insert(unit)
      }
    }
    guard coveredUnitIndices.count == units.offsets.count else {
      throw NativeTermError.invalidPrediction
    }
    try Task.checkCancellation()
    let outputs = try predictOutputs(
      text: text, units: units.offsets, windows: ledger.windows, encoding: encoding)
    try Task.checkCancellation()
    let logits = TermPreprocessor.mergeUnitLogits(
      windowCount: ledger.windows.count, units: units.offsets.count,
      windows: ledger.windows, outputs: outputs).map { $0.map { Float($0) } }
    return try NativeBIODecoder.decode(text: text, logits: logits, offsets: units.offsets)
  }
}
