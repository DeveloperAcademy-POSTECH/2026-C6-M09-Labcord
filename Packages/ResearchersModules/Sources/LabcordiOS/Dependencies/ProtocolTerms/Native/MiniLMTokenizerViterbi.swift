import Foundation

nonisolated extension MiniLMTokenizer {
  /// Unigram Viterbi. word: 정규화 바이트(▁ 접두 포함), charByteLen: 각 스칼라의 utf8 길이.
  /// 반환: (word 내 바이트 범위, HF id) — unk 융합(fuse_unk) 적용.
  func viterbi(_ word: [UInt8], charByteLen: [Int]) -> [(Range<Int>, Int)] {
    let localCount = word.count
    let bound = scalarBounds(charByteLen, count: localCount)
    var buffers = ViterbiBuffers(count: localCount)
    buffers.dynamic[0] = 0
    for localScalarIndex in 0..<charByteLen.count {
      let position = bound[localScalarIndex]
      guard buffers.dynamic[position].isFinite else { continue }
      let scalarEnd = bound[localScalarIndex + 1]
      let hasSingle = compactMode
        ? updateCompact(
          word, position, scalarEnd, localCount, &buffers)
        : updateExpanded(
          word, position, scalarEnd, localCount, &buffers)
      if !hasSingle {
        updateUnknown(position, scalarEnd, &buffers)
      }
    }
    return fuseUnknown(reconstruct(buffers.back, count: localCount))
  }

  private func scalarBounds(_ charByteLen: [Int], count: Int) -> [Int] {
    var bounds = [Int](repeating: count, count: charByteLen.count + 1)
    var localBackPointer = 0
    for (localScalarIndex, localLeft) in charByteLen.enumerated() {
      bounds[localScalarIndex] = localBackPointer
      localBackPointer += localLeft
    }
    bounds[charByteLen.count] = count
    return bounds
  }

  private func updateCompact(
    _ word: [UInt8], _ position: Int, _ scalarEnd: Int, _ localCount: Int,
    _ buffers: inout ViterbiBuffers
  ) -> Bool {
    var hasSingle = false
    var node = flatChild(0, word[position])
    var localNextIndex = position
    while let index = node {
      let leaf = flatNodes[index]
      if leaf.leafID >= 0 {
        updateToken(
          id: Int(leaf.leafID), score: leaf.score, from: position,
          end: localNextIndex + 1, buffers: &buffers)
        if localNextIndex + 1 == scalarEnd { hasSingle = true }
      }
      localNextIndex += 1
      if localNextIndex >= localCount { break }
      node = flatChild(index, word[localNextIndex])
    }
    return hasSingle
  }

  private func updateExpanded(
    _ word: [UInt8], _ position: Int, _ scalarEnd: Int, _ localCount: Int,
    _ buffers: inout ViterbiBuffers
  ) -> Bool {
    var hasSingle = false
    var node: Node? = trie[word[position]]
    var localNextIndex = position
    while let localNode = node {
      if let leaf = localNode.leaf {
        updateToken(
          id: leaf.id, score: leaf.score, from: position,
          end: localNextIndex + 1, buffers: &buffers)
        if localNextIndex + 1 == scalarEnd { hasSingle = true }
      }
      localNextIndex += 1
      if localNextIndex >= localCount { break }
      node = localNode.child[word[localNextIndex]]
    }
    return hasSingle
  }

  private func updateToken(
    id: Int, score: Double, from: Int, end: Int,
    buffers: inout ViterbiBuffers
  ) {
    let candidate = buffers.dynamic[from] + score
    if candidate > buffers.dynamic[end] {
      buffers.dynamic[end] = candidate
      buffers.back[end] = (id, from)
    }
  }

  private func updateUnknown(
    _ position: Int, _ scalarEnd: Int,
    _ buffers: inout ViterbiBuffers
  ) {
    let candidate = buffers.dynamic[position] + unkScore
    if candidate > buffers.dynamic[scalarEnd] {
      buffers.dynamic[scalarEnd] = candidate
      buffers.back[scalarEnd] = (unkId, position)
    }
  }

  private func reconstruct(
    _ back: [(id: Int, from: Int)], count: Int
  ) -> [(Range<Int>, Int)] {
    var output: [(Range<Int>, Int)] = []
    var localPiece = count
    while localPiece > 0 {
      let localEndValue = back[localPiece]
      output.append((localEndValue.from..<localPiece, localEndValue.id))
      localPiece = localEndValue.from
    }
    output.reverse()
    return output
  }

  private func fuseUnknown(_ output: [(Range<Int>, Int)]) -> [(Range<Int>, Int)] {
    var fused: [(Range<Int>, Int)] = []
    for (localResult, id) in output {
      if id == unkId, let last = fused.last, last.1 == unkId,
        last.0.upperBound == localResult.lowerBound {
        fused[fused.count - 1] = (last.0.lowerBound..<localResult.upperBound, unkId)
      } else {
        fused.append((localResult, id))
      }
    }
    return fused
  }
}
