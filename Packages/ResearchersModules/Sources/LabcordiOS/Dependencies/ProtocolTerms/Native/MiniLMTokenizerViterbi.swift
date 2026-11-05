import Foundation

nonisolated extension MiniLMTokenizer {

  func viterbi(_ word: [UInt8], scalarByteLengths: [Int]) -> [(Range<Int>, Int)] {
    let wordByteCount = word.count
    let byteBoundaries = scalarByteBoundaries(scalarByteLengths, count: wordByteCount)
    var buffers = ViterbiBuffers(count: wordByteCount)
    buffers.bestScores[0] = 0
    for scalarIndex in 0..<scalarByteLengths.count {
      let position = byteBoundaries[scalarIndex]
      guard buffers.bestScores[position].isFinite else { continue }
      let scalarEnd = byteBoundaries[scalarIndex + 1]
      let hasSingleScalarToken = usesCompactTrie
        ? updateCompactTrieScores(
          word, position, scalarEnd, wordByteCount, &buffers)
        : updateExpandedTrieScores(
          word, position, scalarEnd, wordByteCount, &buffers)
      if !hasSingleScalarToken {
        updateUnknownTokenScore(position, scalarEnd, &buffers)
      }
    }
    return mergeAdjacentUnknownTokens(
      reconstructTokenPath(buffers.predecessors, count: wordByteCount))
  }

  private func scalarByteBoundaries(_ scalarByteLengths: [Int], count: Int) -> [Int] {
    var bounds = [Int](repeating: count, count: scalarByteLengths.count + 1)
    var byteOffset = 0
    for (scalarIndex, scalarByteLength) in scalarByteLengths.enumerated() {
      bounds[scalarIndex] = byteOffset
      byteOffset += scalarByteLength
    }
    bounds[scalarByteLengths.count] = count
    return bounds
  }

  private func updateCompactTrieScores(
    _ word: [UInt8], _ position: Int, _ scalarEnd: Int, _ wordByteCount: Int,
    _ buffers: inout ViterbiBuffers
  ) -> Bool {
    var hasSingleScalarToken = false
    var node = compactTrieChild(0, word[position])
    var tokenEndByteIndex = position
    while let index = node {
      let leaf = compactTrieNodes[index]
      if leaf.tokenID >= 0 {
        updateToken(
          id: Int(leaf.tokenID), score: leaf.score, from: position,
          end: tokenEndByteIndex + 1, buffers: &buffers)
        if tokenEndByteIndex + 1 == scalarEnd { hasSingleScalarToken = true }
      }
      tokenEndByteIndex += 1
      if tokenEndByteIndex >= wordByteCount { break }
      node = compactTrieChild(index, word[tokenEndByteIndex])
    }
    return hasSingleScalarToken
  }

  private func updateExpandedTrieScores(
    _ word: [UInt8], _ position: Int, _ scalarEnd: Int, _ wordByteCount: Int,
    _ buffers: inout ViterbiBuffers
  ) -> Bool {
    var hasSingleScalarToken = false
    var node: Node? = trie[word[position]]
    var tokenEndByteIndex = position
    while let trieNode = node {
      if let leaf = trieNode.leaf {
        updateToken(
          id: leaf.id, score: leaf.score, from: position,
          end: tokenEndByteIndex + 1, buffers: &buffers)
        if tokenEndByteIndex + 1 == scalarEnd { hasSingleScalarToken = true }
      }
      tokenEndByteIndex += 1
      if tokenEndByteIndex >= wordByteCount { break }
      node = trieNode.child[word[tokenEndByteIndex]]
    }
    return hasSingleScalarToken
  }

  private func updateToken(
    id: Int, score: Double, from: Int, end: Int,
    buffers: inout ViterbiBuffers
  ) {
    let candidate = buffers.bestScores[from] + score
    if candidate > buffers.bestScores[end] {
      buffers.bestScores[end] = candidate
      buffers.predecessors[end] = (id, from)
    }
  }

  private func updateUnknownTokenScore(
    _ position: Int, _ scalarEnd: Int,
    _ buffers: inout ViterbiBuffers
  ) {
    let candidate = buffers.bestScores[position] + unknownTokenScore
    if candidate > buffers.bestScores[scalarEnd] {
      buffers.bestScores[scalarEnd] = candidate
      buffers.predecessors[scalarEnd] = (unknownTokenID, position)
    }
  }

  private func reconstructTokenPath(
    _ predecessors: [(id: Int, from: Int)], count: Int
  ) -> [(Range<Int>, Int)] {
    var output: [(Range<Int>, Int)] = []
    var endByteIndex = count
    while endByteIndex > 0 {
      let predecessor = predecessors[endByteIndex]
      output.append((predecessor.from..<endByteIndex, predecessor.id))
      endByteIndex = predecessor.from
    }
    output.reverse()
    return output
  }

  private func mergeAdjacentUnknownTokens(_ output: [(Range<Int>, Int)]) -> [(Range<Int>, Int)] {
    var fused: [(Range<Int>, Int)] = []
    for (tokenByteRange, id) in output {
      if id == unknownTokenID, let last = fused.last, last.1 == unknownTokenID,
        last.0.upperBound == tokenByteRange.lowerBound {
        fused[fused.count - 1] = (last.0.lowerBound..<tokenByteRange.upperBound, unknownTokenID)
      } else {
        fused.append((tokenByteRange, id))
      }
    }
    return fused
  }
}
