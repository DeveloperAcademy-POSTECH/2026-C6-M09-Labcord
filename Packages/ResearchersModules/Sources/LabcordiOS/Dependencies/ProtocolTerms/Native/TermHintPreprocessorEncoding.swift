import Foundation

nonisolated extension TermPreprocessor {

  public static func characterIDs(
    text: String, unitOffsets: [(Int, Int)], selectedUnitIndices: [Int],
    characterIDsByScalar: [UInt32: Int]
  )
    -> (flat: [Int], unitCharacterOffsets: [Int]) {
    let scalars = Array(text.unicodeScalars)
    var tokenIDs: [Int] = []
    var unitCharacterOffsets = [0]
    for unitIndex in selectedUnitIndices {
      let (startScalarIndex, endScalarIndex) = unitOffsets[unitIndex]
      for scalarIndex in startScalarIndex..<endScalarIndex {
        tokenIDs.append(characterIDsByScalar[scalars[scalarIndex].value] ?? 1)
      }
      unitCharacterOffsets.append(tokenIDs.count)
    }
    return (tokenIDs, unitCharacterOffsets)
  }

  public static func mergeUnitLogits(
    windowCount: Int, units: Int,
    windows: [LedgerWindow],
    outputs: [[[Float]]]
  ) -> [[Double]] {
    var accumulatedLogits = [[Double]](repeating: [0, 0, 0], count: units)
    var predictionCounts = [Int](repeating: 0, count: units)
    for windowIndex in 0..<windowCount {
      let window = windows[windowIndex]
      for (windowUnitIndex, unitIndex) in window.unitIndices.enumerated()
      where window.coreMask[windowUnitIndex] {
        let row = outputs[windowIndex][windowUnitIndex]
        for labelIndex in 0..<3 {
          accumulatedLogits[unitIndex][labelIndex] += Double(row[labelIndex])
        }
        predictionCounts[unitIndex] += 1
      }
    }
    for unitIndex in 0..<units where predictionCounts[unitIndex] > 0 {
      for labelIndex in 0..<3 {
        accumulatedLogits[unitIndex][labelIndex] /= Double(predictionCounts[unitIndex])
      }
    }
    return accumulatedLogits
  }
}
