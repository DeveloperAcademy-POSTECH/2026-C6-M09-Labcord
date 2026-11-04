import Foundation

nonisolated private struct LedgerWindowContext {
  let unitOffsets: [(Int, Int)]
  let unitTokenIndices: [Int]
  let projected: [(Int, Int)?]
  let unitsByAnchorToken: [Int: [Int]]
  let tokenIDs: [Int]
  let unitCount: Int
  let contextUnitCount: Int
  let tokenCapacity: Int
}

nonisolated extension TermPreprocessor {
  private static func anchorLedger(
    text: String, unitOffsets: [(Int, Int)], unsafe: [Bool], rawOffsets: [(Int, Int)]
  ) -> LedgerAnchorState {
    let (projected, reasons) = projectTokens(text, rawOffsets: rawOffsets, unsafe: unsafe)
    let safe = safeTokens(projected, reasons)
    let starts = safe.map { $0.start }
    let centers = ownerCenters(rawOffsets, scalarCount: text.unicodeScalars.count)
    var unitTokenIndices = [Int](repeating: -1, count: unitOffsets.count)
    var anchorTokenIndex = [Int](repeating: -1, count: unitOffsets.count)
    for (unitIndex, offset) in unitOffsets.enumerated() {
      let matched = anchorUnit(offset, safe: safe, starts: starts, centers: centers)
      unitTokenIndices[unitIndex] = matched.token
      anchorTokenIndex[unitIndex] = matched.anchorTokenIndex
    }
    var unitsByAnchorToken: [Int: [Int]] = [:]
    for (unit, token) in anchorTokenIndex.enumerated() {
      unitsByAnchorToken[token, default: []].append(unit)
    }
    return LedgerAnchorState(
      projected: projected, reasons: reasons, unitTokenIndices: unitTokenIndices,
      anchorTokenIndex: anchorTokenIndex, unitsByAnchorToken: unitsByAnchorToken)
  }

  private static func safeTokens(
    _ projected: [(Int, Int)?], _ reasons: [[String]]
  ) -> [SafeToken] {
    var safe: [SafeToken] = []
    for (index, piece) in projected.enumerated()
    where piece != nil && reasons[index].isEmpty {
      if let pair = piece { safe.append(SafeToken(start: pair.0, end: pair.1, index: index)) }
    }
    safe.sort { $0.start < $1.start }
    return safe
  }

  private static func ownerCenters(
    _ rawOffsets: [(Int, Int)], scalarCount: Int
  ) -> [(key: Int, value: Int)] {
    var owners: [Int: Int] = [:]
    for (index, pair) in rawOffsets.enumerated()
    where pair.0 >= 0 && pair.1 > pair.0 && pair.1 <= scalarCount {
      owners[pair.0 + pair.1] = owners[pair.0 + pair.1] ?? index
    }
    return owners.sorted { $0.key < $1.key }
  }

  private static func anchorUnit(
    _ offset: (Int, Int), safe: [SafeToken], starts: [Int],
    centers: [(key: Int, value: Int)]
  ) -> (token: Int, anchorTokenIndex: Int) {
    let (start, end) = offset
    var lower = 0
    var upper = starts.count
    while lower < upper {
      let middle = (lower + upper) / 2
      if starts[middle] <= start { lower = middle + 1 } else { upper = middle }
    }
    let position = lower - 1
    if position >= 0 && end <= safe[position].end {
      return (safe[position].index, safe[position].index)
    }
    guard !centers.isEmpty else { return (-1, -1) }
    let nearest = nearestCenter(start + end, centers: centers)
    return (-1, nearest)
  }

  private static func nearestCenter(
    _ key: Int, centers: [(key: Int, value: Int)]
  ) -> Int {
    var lower = 0
    var upper = centers.count
    while lower < upper {
      let middle = (lower + upper) / 2
      if centers[middle].key < key { lower = middle + 1 } else { upper = middle }
    }
    let lowerIndex = max(0, lower - 1)
    let upperIndex = min(centers.count, lower + 1)
    var best = (abs(centers[lowerIndex].key - key), centers[lowerIndex].value)
    for index in lowerIndex..<upperIndex {
      let candidate = (abs(centers[index].key - key), centers[index].value)
      if candidate < best { best = candidate }
    }
    return best.1
  }

  public static func buildLedger(
    text: String, unitOffsets: [(Int, Int)], unsafe: [Bool],
    rawOffsets: [(Int, Int)], tokenIDs: [Int],
    contextUnitCount: Int = 1, tokenCapacity: Int = 510, windowStride: Int = 446
  ) -> LedgerBuildResult {
    let state = anchorLedger(
      text: text, unitOffsets: unitOffsets, unsafe: unsafe, rawOffsets: rawOffsets)
    let context = LedgerWindowContext(
      unitOffsets: unitOffsets, unitTokenIndices: state.unitTokenIndices,
      projected: state.projected,
      unitsByAnchorToken: state.unitsByAnchorToken, tokenIDs: tokenIDs,
      unitCount: unitOffsets.count,
      contextUnitCount: contextUnitCount, tokenCapacity: tokenCapacity)
    var windows: [LedgerWindow] = []
    var first = 0
    var index = 0
    while true {
      windows.append(buildWindow(context, first: first, includeNegative: index == 0))
      index += 1
      if tokenIDs.isEmpty || first + tokenCapacity >= tokenIDs.count { break }
      first += windowStride
    }
    return LedgerBuildResult(
      windows: windows, unitToSafeToken: state.unitTokenIndices, anchors: state.anchorTokenIndex,
      projected: state.projected, reasons: state.reasons)
  }

  private static func buildWindow(
    _ context: LedgerWindowContext, first: Int, includeNegative: Bool
  ) -> LedgerWindow {
    let sourceTokenCount = context.tokenIDs.count
    let last = min(first + context.tokenCapacity, sourceTokenCount) - 1
    let content: [Int] = sourceTokenCount == 0
      ? [] : (first...max(first, last)).filter { $0 < sourceTokenCount }
    let windowSourceTokenIndices: [Int] = [-1] + content + [-1]
    var windowPositionsBySourceToken: [Int: Int] = [:]
    for (position, globalIndex) in windowSourceTokenIndices.enumerated() where globalIndex >= 0 {
      windowPositionsBySourceToken[globalIndex] = position
    }
    var coreUnitIndices: [Int] = []
    for tokenIndex in content {
      coreUnitIndices.append(contentsOf: context.unitsByAnchorToken[tokenIndex] ?? [])
    }
    if includeNegative { coreUnitIndices.append(contentsOf: context.unitsByAnchorToken[-1] ?? []) }
    coreUnitIndices.sort()
    let selected: [Int]
    if let firstCore = coreUnitIndices.first, let lastCore = coreUnitIndices.last {
      selected = Array(
        max(0, firstCore - context.contextUnitCount) ..<
          min(context.unitCount, lastCore + context.contextUnitCount + 1))
    } else {
      selected = []
    }
    let coreUnitIndexSet = Set(coreUnitIndices)
    var output = WindowUnitOutput()
    for unitIndex in selected {
      appendWindowUnit(
        context, unitIndex: unitIndex,
        windowPositionsBySourceToken: windowPositionsBySourceToken, output: &output)
    }
    return LedgerWindow(
      sourceTokenIndices: windowSourceTokenIndices, unitIndices: selected,
      coreMask: selected.map { coreUnitIndexSet.contains($0) },
      tokenIndices: output.tokenIndices, relativeStarts: output.relativeStarts,
      relativeEnds: output.relativeEnds, mapped: output.mapped)
  }

  private static func appendWindowUnit(
    _ context: LedgerWindowContext, unitIndex: Int, windowPositionsBySourceToken: [Int: Int],
    output: inout WindowUnitOutput
  ) {
    let tokenIndex = context.unitTokenIndices[unitIndex]
    let present = tokenIndex >= 0 && windowPositionsBySourceToken[tokenIndex] != nil
    output.tokenIndices.append(present ? windowPositionsBySourceToken[tokenIndex]! : -1)
    output.mapped.append(present ? 1 : 0)
    if present, let prefixToken = context.projected[tokenIndex] {
      let (unitStart, unitEnd) = context.unitOffsets[unitIndex]
      let denominator = Double(prefixToken.1 - prefixToken.0)
      output.relativeStarts.append(Double(unitStart - prefixToken.0) / denominator)
      output.relativeEnds.append(Double(unitEnd - prefixToken.0) / denominator)
    } else {
      output.relativeStarts.append(0)
      output.relativeEnds.append(0)
    }
  }
}
