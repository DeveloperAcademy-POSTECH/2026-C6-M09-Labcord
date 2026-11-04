import Foundation

nonisolated struct ProtobufReader {
  let bytes: [UInt8]
  var byteIndex = 0
  init(_ data: Data) { bytes = [UInt8](data) }
  init(_ data: [UInt8]) { bytes = data }
  mutating func readVariableLengthInteger() -> UInt64 {
    var result: UInt64 = 0
    var bitShift: UInt64 = 0
    while true {
      let byte = bytes[byteIndex]
      byteIndex += 1
      result |= UInt64(byte & 0x7f) << bitShift
      bitShift += 7
      if byte & 0x80 == 0 { return result }
    }
  }
  mutating func forEachField(_ visitField: (Int, Int, Any) -> Void) {
    while byteIndex < bytes.count {
      let tag = readVariableLengthInteger()
      let field = Int(tag >> 3)
      let wireType = Int(tag & 7)
      switch wireType {
      case 0: visitField(field, wireType, readVariableLengthInteger())
      case 2:
        let fieldByteCount = Int(readVariableLengthInteger())
        visitField(field, wireType, Array(bytes[byteIndex..<byteIndex + fieldByteCount]))
        byteIndex += fieldByteCount
      case 5:
        var value: UInt32 = 0
        for unitIndex in 0..<4 {
          value |= UInt32(bytes[byteIndex + unitIndex]) << UInt32(unitIndex * 8)
        }
        visitField(field, wireType, Float(bitPattern: value))
        byteIndex += 4
      case 1: byteIndex += 8
      default: byteIndex = bytes.count
      }
    }
  }
}

nonisolated struct CharacterNormalizationMap {
  let trie: [UInt32]
  let normalizedBytes: [UInt8]
  init?(blob: [UInt8]) {
    guard blob.count >= 4 else { return nil }
    let trieByteCount = Int(
      UInt32(blob[0]) | UInt32(blob[1]) << 8 | UInt32(blob[2]) << 16 | UInt32(blob[3]) << 24)
    guard 4 + trieByteCount <= blob.count, trieByteCount % 4 == 0 else { return nil }
    var trieUnits = [UInt32](repeating: 0, count: trieByteCount / 4)
    for unitIndex in 0..<trieByteCount / 4 {
      let byteOffset = 4 + unitIndex * 4
      trieUnits[unitIndex] =
        UInt32(blob[byteOffset]) | UInt32(blob[byteOffset + 1]) << 8 | UInt32(
          blob[byteOffset + 2]) << 16 | UInt32(blob[byteOffset + 3]) << 24
    }
    trie = trieUnits
    normalizedBytes = Array(blob[4 + trieByteCount..<blob.count])
  }

  func matchingPrefixes(_ key: ArraySlice<UInt8>) -> [(Int, UInt32)] {
    var node = 0
    var prefixMatches: [(Int, UInt32)] = []
    for (byteIndex, byte) in key.enumerated() {
      let trieUnit = trie[node]

      let nodeOffset = Int(trieUnit >> 10) << Int((trieUnit & 0x200) >> 6)
      let nextNodeIndex = node ^ nodeOffset ^ Int(byte)
      if nextNodeIndex < 0 || nextNodeIndex >= trie.count { break }
      let nextTrieUnit = trie[nextNodeIndex]
      if Int(nextTrieUnit & 0xFF) != Int(byte) { break }
      node = nextNodeIndex
      if (nextTrieUnit >> 8) & 1 == 1 {
        let valueOffset = Int(nextTrieUnit >> 10) << Int((nextTrieUnit & 0x200) >> 6)
        let valueIndex = node ^ valueOffset
        if valueIndex >= 0 && valueIndex < trie.count {
          prefixMatches.append((byteIndex + 1, trie[valueIndex] & 0x7FFF_FFFF))
        }
      }
    }
    return prefixMatches
  }
  func replacement(at value: UInt32) -> ArraySlice<UInt8> {
    var replacementEndIndex = Int(value)
    while replacementEndIndex < normalizedBytes.count
      && normalizedBytes[replacementEndIndex] != 0 {
      replacementEndIndex += 1
    }
    return normalizedBytes[Int(value)..<replacementEndIndex]
  }
}

nonisolated public struct MiniLMTokenizer {
  public let pieces: [String]
  public let scores: [Double]
  let characterNormalizationMap: CharacterNormalizationMap
  let trie: [UInt8: Node]
  let compactTrieNodes: [CompactTrieNode]
  let compactTrieEdges: [CompactTrieEdge]
  let usesCompactTrie: Bool

  nonisolated struct CompactTrieNode {
    var firstEdge: Int32 = -1
    var tokenID: Int32 = -1
    var score: Double = 0
  }

  nonisolated struct CompactTrieEdge {
    let byte: UInt8
    let child: Int32
    let next: Int32
  }

  func compactTrieChild(_ index: Int, _ byte: UInt8) -> Int? {
    var edge = compactTrieNodes[index].firstEdge
    while edge >= 0 {
      let value = compactTrieEdges[Int(edge)]
      if value.byte == byte { return Int(value.child) }
      edge = value.next
    }
    return nil
  }

  public let unknownTokenID = 3, startTokenID = 0, endTokenID = 2
  let unknownTokenScore: Double

  nonisolated final class Node {
    var child: [UInt8: Node] = [:]
    var leaf: (id: Int, score: Double)?
  }

  public func normalizeWithSourceRanges(_ utf8: [UInt8], byteScalar: [Int])
    -> (normalizedBytes: [UInt8], sourceScalarRanges: [ClosedRange<Int>]) {
    var normalizedBytes = [UInt8]()
    var sourceScalarRanges = [ClosedRange<Int>]()
    var byteIndex = 0
    while byteIndex < utf8.count {
      let prefixMatches = characterNormalizationMap.matchingPrefixes(
        utf8[byteIndex..<min(utf8.count, byteIndex + 24)])
      if let (localLength, value) = prefixMatches.last {
        let replacementBytes = characterNormalizationMap.replacement(at: value)
        let sourceScalarIndex = byteScalar[byteIndex]
        for _ in replacementBytes {
          sourceScalarRanges.append(sourceScalarIndex...sourceScalarIndex)
        }
        normalizedBytes.append(contentsOf: replacementBytes)
        byteIndex += localLength
      } else {
        normalizedBytes.append(utf8[byteIndex])
        sourceScalarRanges.append(byteScalar[byteIndex]...byteScalar[byteIndex])
        byteIndex += 1
      }
    }
    return (normalizedBytes, sourceScalarRanges)
  }
}
