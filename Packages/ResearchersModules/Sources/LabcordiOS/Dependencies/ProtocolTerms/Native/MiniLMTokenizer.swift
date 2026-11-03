// MiniLMTokenizer.swift — sentencepiece.bpe.model (unigram) 인코더 순수 Swift 포트.
// 참조: HF tokenizers Unigram + Precompiled(nmt_nfkc) + WhitespaceSplit/Metaspace.
// vocab id는 HF tokenizer 인덱스: proto idx p -> p+1 (스페셜 <s>=0,<pad>=1,</s>=2,<unk>=3).
import Foundation

nonisolated struct ProtoReader {
  let localEnd: [UInt8]
  var localIndex = 0
  init(_ localData: Data) { localEnd = [UInt8](localData) }
  init(_ localData: [UInt8]) { localEnd = localData }
  mutating func varint() -> UInt64 {
    var localResult: UInt64 = 0
    var localString: UInt64 = 0
    while true {
      let localInput = localEnd[localIndex]
      localIndex += 1
      localResult |= UInt64(localInput & 0x7f) << localString
      localString += 7
      if localInput & 0x80 == 0 { return localResult }
    }
  }
  mutating func eachField(_ localField: (Int, Int, Any) -> Void) {
    while localIndex < localEnd.count {
      let tag = varint()
      let field = Int(tag >> 3)
      let localWireType = Int(tag & 7)
      switch localWireType {
      case 0: localField(field, localWireType, varint())
      case 2:
        let localCount = Int(varint())
        localField(field, localWireType, Array(localEnd[localIndex..<localIndex + localCount]))
        localIndex += localCount
      case 5:
        var localValue: UInt32 = 0
        for localLimit in 0..<4 {
          localValue |= UInt32(localEnd[localIndex + localLimit]) << UInt32(localLimit * 8)
        }
        localField(field, localWireType, Float(bitPattern: localValue))
        localIndex += 4
      case 1: localIndex += 8
      default: localIndex = localEnd.count
      }
    }
  }
}

/// precompiled charsmap: [u32 trie_byte_size][darts trie][norm blob]
nonisolated struct CharsMap {
  let trie: [UInt32]
  let norm: [UInt8]
  init?(blob: [UInt8]) {
    guard blob.count >= 4 else { return nil }
    let localTrieBytes = Int(
      UInt32(blob[0]) | UInt32(blob[1]) << 8 | UInt32(blob[2]) << 16 | UInt32(blob[3]) << 24)
    guard 4 + localTrieBytes <= blob.count, localTrieBytes % 4 == 0 else { return nil }
    var localToken = [UInt32](repeating: 0, count: localTrieBytes / 4)
    for localLimit in 0..<localTrieBytes / 4 {
      let localOffset = 4 + localLimit * 4
      localToken[localLimit] =
        UInt32(blob[localOffset]) | UInt32(blob[localOffset + 1]) << 8 | UInt32(
          blob[localOffset + 2]) << 16 | UInt32(blob[localOffset + 3]) << 24
    }
    trie = localToken
    norm = Array(blob[4 + localTrieBytes..<blob.count])
  }
  /// 모든 매치된 접두어 (소비 바이트 수, norm 오프셋) — 오름차순
  func commonPrefix(_ key: ArraySlice<UInt8>) -> [(Int, UInt32)] {
    var node = 0
    var res: [(Int, UInt32)] = []
    for (localIndex, localCandidate) in key.enumerated() {
      let localUnit = trie[node]
      // darts-clone offset(): (unit >> 10) << ((unit & 0x200) >> 6)
      let off = Int(localUnit >> 10) << Int((localUnit & 0x200) >> 6)
      let nxt = node ^ off ^ Int(localCandidate)
      if nxt < 0 || nxt >= trie.count { break }
      let localUnitValue = trie[nxt]
      if Int(localUnitValue & 0xFF) != Int(localCandidate) { break }
      node = nxt
      if (localUnitValue >> 8) & 1 == 1 {
        let voff = Int(localUnitValue >> 10) << Int((localUnitValue & 0x200) >> 6)
        let vidx = node ^ voff
        if vidx >= 0 && vidx < trie.count {
          res.append((localIndex + 1, trie[vidx] & 0x7FFF_FFFF))
        }
      }
    }
    return res
  }
  func replacement(at localValue: UInt32) -> ArraySlice<UInt8> {
    var localEndValue = Int(localValue)
    while localEndValue < norm.count && norm[localEndValue] != 0 { localEndValue += 1 }
    return norm[Int(localValue)..<localEndValue]
  }
}

nonisolated public struct MiniLMTokenizer {
  public let pieces: [String]
  public let scores: [Double]
  let types: [Int]
  let charsmap: CharsMap
  let idOf: [String: Int]
  let trie: [UInt8: Node]
  let flatNodes: [FlatNode]
  let flatEdges: [FlatEdge]
  let compactMode: Bool

  nonisolated struct FlatNode {
    var firstEdge: Int32 = -1
    var leafID: Int32 = -1
    var score: Double = 0
  }

  nonisolated struct FlatEdge {
    let byte: UInt8
    let child: Int32
    let next: Int32
  }

  func flatChild(_ index: Int, _ byte: UInt8) -> Int? {
    var edge = flatNodes[index].firstEdge
    while edge >= 0 {
      let value = flatEdges[Int(edge)]
      if value.byte == byte { return Int(value.child) }
      edge = value.next
    }
    return nil
  }

  public let unkId = 3, clsId = 0, sepId = 2
  let unkScore: Double

  nonisolated final class Node {
    var child: [UInt8: Node] = [:]
    var leaf: (id: Int, score: Double)?
  }

  /// 정규화: 최장 바이트 접두 매치 치환 / 미매칭 1바이트 통과.
  /// 반환: 정규화 utf8 바이트 + 각 출력 바이트의 원문 스칼라 범위.
  public func normalizeMapped(_ utf8: [UInt8], byteScalar: [Int])
    -> (norm: [UInt8], src: [ClosedRange<Int>]) {
    var out = [UInt8]()
    var src = [ClosedRange<Int>]()
    var localIndex = 0
    while localIndex < utf8.count {
      let res = charsmap.commonPrefix(utf8[localIndex..<min(utf8.count, localIndex + 24)])
      if let (localLength, localValue) = res.last {
        let rep = charsmap.replacement(at: localValue)
        let localStart = byteScalar[localIndex]
        for _ in rep { src.append(localStart...localStart) }
        out.append(contentsOf: rep)
        localIndex += localLength
      } else {
        out.append(utf8[localIndex])
        src.append(byteScalar[localIndex]...byteScalar[localIndex])
        localIndex += 1
      }
    }
    return (out, src)
  }
}
