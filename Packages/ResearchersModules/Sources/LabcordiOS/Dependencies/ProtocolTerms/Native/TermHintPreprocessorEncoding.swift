import Foundation

nonisolated extension TermPreprocessor {
  /// window_features → char_ids (unit당 가변), unit_char_offsets 간접형.
  public static func charIds(
    text: String, unitOffsets: [(Int, Int)], sel: [Int], charMap: [UInt32: Int]
  )
    -> (flat: [Int], unitCharOffsets: [Int]) {
    let scalars = Array(text.unicodeScalars)
    var ids: [Int] = []
    var ptr = [0]
    for localUnit in sel {
      let (localStart, localEnd) = unitOffsets[localUnit]
      for localScalarIndex in localStart..<localEnd {
        ids.append(charMap[scalars[localScalarIndex].value] ?? 1)
      }
      ptr.append(ids.count)
    }
    return (ids, ptr)
  }

  /// merge_unit_logits: core 유닛 로짓의 단순 평균(Double).
  public static func mergeUnitLogits(
    windowCount: Int, units: Int,
    windows: [LedgerWindow],
    outputs: [[[Float]]]
  ) -> [[Double]] {
    var acc = [[Double]](repeating: [0, 0, 0], count: units)
    var cnt = [Int](repeating: 0, count: units)
    for localWindowIndex in 0..<windowCount {
      let localWidth = windows[localWindowIndex]
      for (localNextIndex, localUnit) in localWidth.unitIndices.enumerated()
      where localWidth.coreMask[localNextIndex] {
        let row = outputs[localWindowIndex][localNextIndex]
        for localLimit in 0..<3 { acc[localUnit][localLimit] += Double(row[localLimit]) }
        cnt[localUnit] += 1
      }
    }
    for localUnit in 0..<units where cnt[localUnit] > 0 {
      for localLimit in 0..<3 { acc[localUnit][localLimit] /= Double(cnt[localUnit]) }
    }
    return acc
  }
}
