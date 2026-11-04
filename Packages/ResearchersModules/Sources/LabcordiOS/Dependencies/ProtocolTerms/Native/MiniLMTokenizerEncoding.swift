import Foundation

nonisolated extension MiniLMTokenizer {

  public func encode(_ text: String) -> (tokenIDs: [Int], offsets: [(Int, Int)]) {
    let source = normalizedSource(text)
    var tokenIDs: [Int] = []
    var offsets: [(Int, Int)] = []
    encodeWords(source, tokenIDs: &tokenIDs, offsets: &offsets)
    return (tokenIDs, offsets)
  }

  private func normalizedSource(_ text: String) -> NormalizedSource {

    let scalars = Array(text.unicodeScalars)
    var utf8: [UInt8] = []
    var byteScalar: [Int] = []
    utf8.reserveCapacity(text.utf8.count)
    byteScalar.reserveCapacity(text.utf8.count)
    for (scalarIndex, scalar) in scalars.enumerated() {
      for bytePosition in String(scalar).utf8 {
        utf8.append(bytePosition)
        byteScalar.append(scalarIndex)
      }
    }
    let mapped = normalizeWithSourceRanges(utf8, byteScalar: byteScalar)
    return NormalizedSource(
      normalizedBytes: mapped.normalizedBytes, sourceScalarRanges: mapped.sourceScalarRanges)
  }

  private func encodeWords(
    _ source: NormalizedSource, tokenIDs: inout [Int], offsets: inout [(Int, Int)]
  ) {
    let normalizedBytes = source.normalizedBytes
    let sourceScalarRanges = source.sourceScalarRanges

    var wordStart = 0
    while wordStart < normalizedBytes.count {
      var prefixSourceRange: (Int, Int)?
      while wordStart < normalizedBytes.count && normalizedBytes[wordStart] == 0x20 {
        wordStart += 1
      }
      if wordStart > 0 && normalizedBytes[wordStart - 1] == 0x20 {
        let whitespaceRange = sourceScalarRanges[wordStart - 1]
        prefixSourceRange = (whitespaceRange.lowerBound, whitespaceRange.upperBound + 1)
      }
      if wordStart >= normalizedBytes.count { break }
      var wordEnd = wordStart
      while wordEnd < normalizedBytes.count && normalizedBytes[wordEnd] != 0x20 { wordEnd += 1 }

      var word: [UInt8] = [0xE2, 0x96, 0x81]
      word.append(contentsOf: normalizedBytes[wordStart..<wordEnd])
      var scalarByteLengths: [Int] = [3]
      var bytePosition = wordStart
      while bytePosition < wordEnd {
        let firstByte = normalizedBytes[bytePosition]
        let scalarByteLength =
          firstByte < 0x80 ? 1 : (firstByte < 0xE0 ? 2 : (firstByte < 0xF0 ? 3 : 4))
        scalarByteLengths.append(scalarByteLength)
        bytePosition += scalarByteLength
      }
      let wordTokens = viterbi(word, scalarByteLengths: scalarByteLengths)
      for (tokenByteRange, id) in wordTokens {
        tokenIDs.append(id)

        let sourceStartByteIndex = max(tokenByteRange.lowerBound, 3) - 3 + wordStart
        let sourceEndByteIndex = max(tokenByteRange.upperBound, 3) - 3 + wordStart
        var sourceStartScalarIndex: Int
        var sourceEndScalarIndex: Int
        if tokenByteRange.upperBound <= 3 {

          sourceStartScalarIndex = prefixSourceRange?.0
            ?? (sourceStartByteIndex < sourceScalarRanges.count
              ? sourceScalarRanges[sourceStartByteIndex].lowerBound : 0)
          sourceEndScalarIndex = prefixSourceRange?.1
            ?? (sourceStartByteIndex < sourceScalarRanges.count
              ? sourceScalarRanges[sourceStartByteIndex].upperBound + 1 : sourceStartScalarIndex)
        } else {
          sourceStartScalarIndex = tokenByteRange.lowerBound < 3
            ? (prefixSourceRange?.0 ?? sourceScalarRanges[sourceStartByteIndex].lowerBound)
            : sourceScalarRanges[sourceStartByteIndex].lowerBound
          sourceEndScalarIndex = sourceScalarRanges[sourceEndByteIndex - 1].upperBound + 1
        }
        offsets.append((sourceStartScalarIndex, sourceEndScalarIndex))
      }
      wordStart = wordEnd
    }
  }

  public func windows(tokenIDs: [Int]) -> [[Int]] {
    var tokenWindows: [[Int]] = []
    let tokenCount = tokenIDs.count
    if tokenCount == 0 { return [[startTokenID, endTokenID]] }
    var first = 0
    while true {
      var windowTokenIDs = [startTokenID]
      windowTokenIDs.append(contentsOf: tokenIDs[first..<min(first + 510, tokenCount)])
      windowTokenIDs.append(endTokenID)
      tokenWindows.append(windowTokenIDs)
      if first + 510 >= tokenCount { break }
      first += 446
    }
    return tokenWindows
  }
}
