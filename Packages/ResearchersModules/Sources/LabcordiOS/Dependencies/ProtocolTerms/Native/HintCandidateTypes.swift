import Foundation

nonisolated struct ViterbiBuffers {
  var bestScores: [Double]
  var predecessors: [(id: Int, from: Int)]

  init(count: Int) {
    bestScores = [Double](repeating: -Double.infinity, count: count + 1)
    predecessors = [(id: Int, from: Int)](repeating: (-1, -1), count: count + 1)
  }
}

nonisolated struct NormalizedSource {
  let normalizedBytes: [UInt8]
  let sourceScalarRanges: [ClosedRange<Int>]
}

nonisolated struct ParsedPiece {
  let name: String
  let score: Double
  let type: Int
}

nonisolated struct WindowUnitOutput {
  var tokenIndices: [Int] = []
  var relativeStarts: [Double] = []
  var relativeEnds: [Double] = []
  var mapped: [Int] = []
}

nonisolated struct LedgerAnchorState {
  let projected: [(Int, Int)?]
  let reasons: [[String]]
  let unitTokenIndices: [Int]
  let anchorTokenIndex: [Int]
  let unitsByAnchorToken: [Int: [Int]]
}

nonisolated struct SafeToken {
  let start: Int
  let end: Int
  let index: Int
}

nonisolated public struct SafeUnitResult {
  public let offsets: [(Int, Int)]
  public let unsafe: [Bool]
  public let scalarUTF16Offsets: [Int]

  public init(offsets: [(Int, Int)], unsafe: [Bool], scalarUTF16Offsets: [Int]) {
    self.offsets = offsets
    self.unsafe = unsafe
    self.scalarUTF16Offsets = scalarUTF16Offsets
  }
}

nonisolated public struct LedgerBuildResult {
  public let windows: [TermPreprocessor.LedgerWindow]
  public let unitToSafeToken: [Int]
  public let anchors: [Int]
  public let projected: [(Int, Int)?]
  public let reasons: [[String]]

  public init(
    windows: [TermPreprocessor.LedgerWindow], unitToSafeToken: [Int], anchors: [Int],
    projected: [(Int, Int)?], reasons: [[String]]
  ) {
    self.windows = windows
    self.unitToSafeToken = unitToSafeToken
    self.anchors = anchors
    self.projected = projected
    self.reasons = reasons
  }
}
