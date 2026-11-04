import Foundation

nonisolated struct ViterbiBuffers {
  var dynamic: [Double]
  var back: [(id: Int, from: Int)]

  init(count: Int) {
    dynamic = [Double](repeating: -Double.infinity, count: count + 1)
    back = [(id: Int, from: Int)](repeating: (-1, -1), count: count + 1)
  }
}

nonisolated struct NormalizedSource {
  let norm: [UInt8]
  let src: [ClosedRange<Int>]
}

nonisolated struct ParsedPiece {
  let name: String
  let score: Double
  let type: Int
}

nonisolated struct WindowUnitOutput {
  var tokenIndices: [Int] = []
  var rangeStart: [Double] = []
  var rangeEnd: [Double] = []
  var mapped: [Int] = []
}

nonisolated struct LedgerAnchorState {
  let projected: [(Int, Int)?]
  let reasons: [[String]]
  let unitToken: [Int]
  let anchor: [Int]
  let anchored: [Int: [Int]]
}

nonisolated struct SafeToken {
  let start: Int
  let end: Int
  let index: Int
}

nonisolated public struct SafeUnitResult {
  public let offsets: [(Int, Int)]
  public let unsafe: [Bool]
  public let cp16: [Int]

  public init(offsets: [(Int, Int)], unsafe: [Bool], cp16: [Int]) {
    self.offsets = offsets
    self.unsafe = unsafe
    self.cp16 = cp16
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
