import Foundation

nonisolated private struct LedgerWindowContext {
  let unitOffsets: [(Int, Int)]
  let unitToken: [Int]
  let projected: [(Int, Int)?]
  let anchored: [Int: [Int]]
  let flatIds: [Int]
  let localCount: Int
  let halo: Int
  let cap: Int
}

nonisolated extension TermPreprocessor {
  private static func anchorLedger(
    text: String, unitOffsets: [(Int, Int)], unsafe: [Bool], rawOffsets: [(Int, Int)]
  ) -> LedgerAnchorState {
    let (projected, reasons) = projectTokens(text, rawOffsets: rawOffsets, unsafe: unsafe)
    let safe = safeTokens(projected, reasons)
    let starts = safe.map { $0.start }
    let centers = ownerCenters(rawOffsets, scalarCount: text.unicodeScalars.count)
    var unitToken = [Int](repeating: -1, count: unitOffsets.count)
    var anchor = [Int](repeating: -1, count: unitOffsets.count)
    for (unitIndex, offset) in unitOffsets.enumerated() {
      let matched = anchorUnit(offset, safe: safe, starts: starts, centers: centers)
      unitToken[unitIndex] = matched.token
      anchor[unitIndex] = matched.anchor
    }
    var anchored: [Int: [Int]] = [:]
    for (unit, token) in anchor.enumerated() { anchored[token, default: []].append(unit) }
    return LedgerAnchorState(
      projected: projected, reasons: reasons, unitToken: unitToken,
      anchor: anchor, anchored: anchored)
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
  ) -> (token: Int, anchor: Int) {
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

  /// build_source_projection: 단위→토큰 앵커 + 윈도우별 선택/halo.
  public static func buildLedger(
    text: String, unitOffsets: [(Int, Int)], unsafe: [Bool],
    rawOffsets: [(Int, Int)], flatIds: [Int],
    halo: Int = 1, cap: Int = 510, step: Int = 446
  ) -> LedgerBuildResult {
    let state = anchorLedger(
      text: text, unitOffsets: unitOffsets, unsafe: unsafe, rawOffsets: rawOffsets)
    let context = LedgerWindowContext(
      unitOffsets: unitOffsets, unitToken: state.unitToken, projected: state.projected,
      anchored: state.anchored, flatIds: flatIds, localCount: unitOffsets.count,
      halo: halo, cap: cap)
    var windows: [LedgerWindow] = []
    var first = 0
    var index = 0
    while true {
      windows.append(buildWindow(context, first: first, includeNegative: index == 0))
      index += 1
      if flatIds.isEmpty || first + cap >= flatIds.count { break }
      first += step
    }
    return LedgerBuildResult(
      windows: windows, unitToSafeToken: state.unitToken, anchors: state.anchor,
      projected: state.projected, reasons: state.reasons)
  }

  private static func buildWindow(
    _ context: LedgerWindowContext, first: Int, includeNegative: Bool
  ) -> LedgerWindow {
    let threshold = context.flatIds.count
    let last = min(first + context.cap, threshold) - 1
    let content: [Int] = threshold == 0
      ? [] : (first...max(first, last)).filter { $0 < threshold }
    let flat: [Int] = [-1] + content + [-1]
    var local: [Int: Int] = [:]
    for (position, globalIndex) in flat.enumerated() where globalIndex >= 0 {
      local[globalIndex] = position
    }
    var core: [Int] = []
    for localToken in content { core.append(contentsOf: context.anchored[localToken] ?? []) }
    if includeNegative { core.append(contentsOf: context.anchored[-1] ?? []) }
    core.sort()
    let selected: [Int]
    if let firstCore = core.first, let lastCore = core.last {
      selected = Array(
        max(0, firstCore - context.halo)..<min(context.localCount, lastCore + context.halo + 1))
    } else {
      selected = []
    }
    let coreSet = Set(core)
    var output = WindowUnitOutput()
    for localUnit in selected {
      appendWindowUnit(
        context, localUnit: localUnit, local: local, output: &output)
    }
    return LedgerWindow(
      flatIndices: flat, unitIndices: selected, coreMask: selected.map { coreSet.contains($0) },
      tokenIndices: output.tokenIndices, relStart: output.rangeStart,
      relEnd: output.rangeEnd, mapped: output.mapped)
  }

  private static func appendWindowUnit(
    _ context: LedgerWindowContext, localUnit: Int, local: [Int: Int],
    output: inout WindowUnitOutput
  ) {
    let localToken = context.unitToken[localUnit]
    let present = localToken >= 0 && local[localToken] != nil
    output.tokenIndices.append(present ? local[localToken]! : -1)
    output.mapped.append(present ? 1 : 0)
    if present, let prefixToken = context.projected[localToken] {
      let (unitStart, valueStart) = context.unitOffsets[localUnit]
      let denominator = Double(prefixToken.1 - prefixToken.0)
      output.rangeStart.append(Double(unitStart - prefixToken.0) / denominator)
      output.rangeEnd.append(Double(valueStart - prefixToken.0) / denominator)
    } else {
      output.rangeStart.append(0)
      output.rangeEnd.append(0)
    }
  }
}
