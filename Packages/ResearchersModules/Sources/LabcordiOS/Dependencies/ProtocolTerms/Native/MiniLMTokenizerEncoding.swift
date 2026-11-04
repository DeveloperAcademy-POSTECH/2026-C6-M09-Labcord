import Foundation

nonisolated extension MiniLMTokenizer {
  /// 전체 인코딩: 텍스트 -> (flat ids, raw offsets[원문 스칼라 범위])
  /// HF 파이프: Precompiled 정규화 -> 공백 분할 + ▁ 접두(Metaspace) -> unigram viterbi (fuse_unk)
  public func encode(_ text: String) -> (ids: [Int], offsets: [(Int, Int)]) {
    let source = normalizedSource(text)
    var ids: [Int] = []
    var offsets: [(Int, Int)] = []
    encodeWords(source, ids: &ids, offsets: &offsets)
    return (ids, offsets)
  }

  private func normalizedSource(_ text: String) -> NormalizedSource {
    // 원문 스칼라 -> utf8 바이트 매핑
    let scalars = Array(text.unicodeScalars)
    var utf8: [UInt8] = []
    var byteScalar: [Int] = []
    utf8.reserveCapacity(text.utf8.count)
    byteScalar.reserveCapacity(text.utf8.count)
    for (localScalarIndex, localScore) in scalars.enumerated() {
      for localEnd in String(localScore).utf8 {
        utf8.append(localEnd)
        byteScalar.append(localScalarIndex)
      }
    }
    let mapped = normalizeMapped(utf8, byteScalar: byteScalar)
    return NormalizedSource(norm: mapped.norm, src: mapped.src)
  }

  private func encodeWords(
    _ source: NormalizedSource, ids: inout [Int], offsets: inout [(Int, Int)]
  ) {
    let norm = source.norm
    let src = source.src
    // 공백 분할(ASCII ' ' 기준) — HF WhitespaceSplit+Metaspace는 공백 시퀀스를 소비한다.
    var localIndex = 0
    while localIndex < norm.count {
      var prefixSrc: (Int, Int)?
      while localIndex < norm.count && norm[localIndex] == 0x20 { localIndex += 1 }
      if localIndex > 0 && norm[localIndex - 1] == 0x20 {
        let localString = src[localIndex - 1]  // 마지막 공백의 원문 스칼라 범위
        prefixSrc = (localString.lowerBound, localString.upperBound + 1)
      }
      if localIndex >= norm.count { break }
      var localNextIndex = localIndex
      while localNextIndex < norm.count && norm[localNextIndex] != 0x20 { localNextIndex += 1 }
      // 단어 정규화 바이트 norm[i..<j], ▁ 접두(0xE2 0x96 0x81) 포함 viterbi 입력
      var word: [UInt8] = [0xE2, 0x96, 0x81]
      word.append(contentsOf: norm[localIndex..<localNextIndex])
      var clen: [Int] = [3]
      var localEnd = localIndex
      while localEnd < localNextIndex {
        let localCandidate = norm[localEnd]
        let localLeft =
          localCandidate < 0x80 ? 1 : (localCandidate < 0xE0 ? 2 : (localCandidate < 0xF0 ? 3 : 4))
        clen.append(localLeft)
        localEnd += localLeft
      }
      let toks = viterbi(word, charByteLen: clen)
      for (localResult, id) in toks {
        ids.append(id)
        // 바이트 범위 r: 3 바이트 접두는 가상(스칼라 매핑 없음).
        let localLowerBound = max(localResult.lowerBound, 3) - 3 + localIndex
        let localUpperBound = max(localResult.upperBound, 3) - 3 + localIndex
        var localStartA: Int
        var localStartB: Int
        if localResult.upperBound <= 3 {
          // '▁' 전용 조각: 직전 마지막 공백에 매핑
          localStartA =
            prefixSrc?.0 ?? (localLowerBound < src.count ? src[localLowerBound].lowerBound : 0)
          localStartB =
            prefixSrc?.1
            ?? (localLowerBound < src.count ? src[localLowerBound].upperBound + 1 : localStartA)
        } else {
          localStartA =
            localResult.lowerBound < 3
            ? (prefixSrc?.0 ?? src[localLowerBound].lowerBound) : src[localLowerBound].lowerBound
          localStartB = src[localUpperBound - 1].upperBound + 1
        }
        offsets.append((localStartA, localStartB))
      }
      localIndex = localNextIndex
    }
  }

  /// HF overflow window: content 용량 510, step 446, [CLS]/[SEP] 래핑.
  /// 빈 입력은 빈 윈도우 없이 반환하지 않고 특수 토큰만 있는 1창을 반환한다(HF 동작 동일 가정).
  public func windows(ids: [Int]) -> [[Int]] {
    var out: [[Int]] = []
    let localCount = ids.count
    if localCount == 0 { return [[clsId, sepId]] }
    var first = 0
    while true {
      var localWidth = [clsId]
      localWidth.append(contentsOf: ids[first..<min(first + 510, localCount)])
      localWidth.append(sepId)
      out.append(localWidth)
      if first + 510 >= localCount { break }
      first += 446
    }
    return out
  }
}
