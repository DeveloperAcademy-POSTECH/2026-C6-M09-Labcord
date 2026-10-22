import CoreGraphics
import Foundation
import PDFKit

/// 연결된 가로·세로 선분에서 격자를 찾고, 경계가 없는 이웃 칸을 병합 셀로 묶는다.
/// 텍스트 선택이 가능한 PDF용이며 스캔 이미지의 표 셀을 복원하지 않는다.
nonisolated enum DocumentPDFTableExtractor {
  struct Result {
    var blocks: [DocumentBlock] = []
    var warnings: [DocumentWarning] = []
  }

  private struct Grid {
    let columnEdges: [CGFloat]
    let rowEdges: [CGFloat]
    let lines: [Line]
  }

  private struct Line {
    let vertical: Bool
    let coordinate: CGFloat
    let lower: CGFloat
    let upper: CGFloat

    func touches(_ other: Line) -> Bool {
      if vertical == other.vertical {
        return abs(coordinate - other.coordinate) < 1
          && lower <= other.upper + 1 && upper >= other.lower - 1
      }
      return coordinate >= other.lower - 1 && coordinate <= other.upper + 1
        && other.coordinate >= lower - 1 && other.coordinate <= upper + 1
    }
  }

  static func extract(
    segments: [DocumentPDFScanner.Segment],
    page: PDFPage,
    pageIndex: Int,
    space: DocumentPDFPageSpace
  ) throws -> Result {
    let lines = segments.compactMap(line)
    var unseen = Set(lines.indices)
    var result = Result()
    var tableIndex = 0
    while let seed = unseen.min() {
      try Task.checkCancellation()
      unseen.remove(seed)
      var component = [seed]
      var cursor = 0
      while cursor < component.count {
        let neighbours = unseen.filter { lines[component[cursor]].touches(lines[$0]) }
        unseen.subtract(neighbours)
        component.append(contentsOf: neighbours.sorted())
        cursor += 1
      }
      let group = component.map { lines[$0] }
      let columnEdges = coordinates(group.filter(\.vertical).map(\.coordinate))
      let rowEdges = coordinates(group.filter { !$0.vertical }.map(\.coordinate)).reversed()
      guard columnEdges.count >= 2, rowEdges.count >= 2,
        columnEdges.count + rowEdges.count > 4
      else { continue }
      let location = DocumentLocation(part: "table[\(tableIndex)]", page: pageIndex + 1)
      guard columnEdges.count * rowEdges.count <= 1_024 else {
        result.warnings.append(
          DocumentWarning(
            code: .resourceLimitReached, message: "PDF table grid exceeded the cell limit.",
            location: location))
        continue
      }
      let table = extractGrid(
        Grid(columnEdges: columnEdges, rowEdges: Array(rowEdges), lines: group),
        page: page, space: space, location: location)
      if !table.blocks.isEmpty { tableIndex += 1 }
      result.blocks.append(contentsOf: table.blocks)
      result.warnings.append(contentsOf: table.warnings)
    }
    return result
  }

  private static func line(_ segment: DocumentPDFScanner.Segment) -> Line? {
    let deltaX = abs(segment.end.x - segment.start.x)
    let deltaY = abs(segment.end.y - segment.start.y)
    guard max(deltaX, deltaY) > 3 else { return nil }
    if deltaX < 0.5 {
      return Line(
        vertical: true, coordinate: segment.start.x,
        lower: min(segment.start.y, segment.end.y), upper: max(segment.start.y, segment.end.y))
    }
    if deltaY < 0.5 {
      return Line(
        vertical: false, coordinate: segment.start.y,
        lower: min(segment.start.x, segment.end.x), upper: max(segment.start.x, segment.end.x))
    }
    return nil
  }

  private static func coordinates(_ values: [CGFloat]) -> [CGFloat] {
    values.sorted().reduce(into: []) { result, value in
      if let last = result.last, abs(last - value) < 1 { return }
      result.append(value)
    }
  }

  /// 짧게 끊긴 선분도 이어진 경계인지 확인한다. 선 하나의 길이만 보고 셀을 병합하지 않는다.
  private static func covers(
    _ lines: [Line], vertical: Bool, at coordinate: CGFloat, from lower: CGFloat, to upper: CGFloat
  ) -> Bool {
    let matches = lines.filter { $0.vertical == vertical && abs($0.coordinate - coordinate) < 1 }
      .sorted { $0.lower < $1.lower }
    var cursor = lower
    for match in matches where match.upper >= cursor - 1 {
      if match.lower > cursor + 1 { return false }
      cursor = max(cursor, match.upper)
      if cursor >= upper - 1 { return true }
    }
    return false
  }

  private static func extractGrid(
    _ grid: Grid, page: PDFPage, space: DocumentPDFPageSpace, location: DocumentLocation
  ) -> Result {
    let columnEdges = grid.columnEdges
    let rowEdges = grid.rowEdges
    let lines = grid.lines
    let columns = columnEdges.count - 1
    let rows = rowEdges.count - 1
    let bounds = CGRect(
      x: columnEdges[0], y: rowEdges[rows],
      width: columnEdges[columns] - columnEdges[0], height: rowEdges[0] - rowEdges[rows])
    guard !(page.selection(for: bounds)?.string ?? "").isEmpty else { return Result() }
    let labels = mergeCells(columnEdges: columnEdges, rowEdges: rowEdges, lines: lines)
    var result = Result()
    var tableLocation = location
    tableLocation.bounds = space.normalized(bounds)
    result.blocks.append(
      DocumentBlock(
        kind: .table, text: "", readingOrder: 0, location: tableLocation))
    for label in Set(labels).sorted() {
      let members = labels.indices.filter { labels[$0] == label }
      let cellRows = members.map { $0 / columns }
      let cellColumns = members.map { $0 % columns }
      guard let top = cellRows.min(), let bottom = cellRows.max(),
        let left = cellColumns.min(), let right = cellColumns.max()
      else { continue }
      guard members.count == (bottom - top + 1) * (right - left + 1) else {
        result.warnings.append(
          DocumentWarning(
            code: .uncertainReadingOrder,
            message: "An irregular PDF table cell could not be resolved.",
            location: tableLocation))
        return Result(blocks: [], warnings: result.warnings)
      }
      let rect = CGRect(
        x: columnEdges[left], y: rowEdges[bottom + 1],
        width: columnEdges[right + 1] - columnEdges[left],
        height: rowEdges[top] - rowEdges[bottom + 1])
      let value = (page.selection(for: rect.insetBy(dx: 0.5, dy: 0.5))?.string ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      var cellLocation = location
      cellLocation.row = top + 1
      cellLocation.column = left + 1
      cellLocation.rowSpan = bottom - top + 1
      cellLocation.columnSpan = right - left + 1
      cellLocation.bounds = space.normalized(rect)
      result.blocks.append(
        DocumentBlock(
          kind: .tableCell, text: value, readingOrder: result.blocks.count, location: cellLocation)
      )
    }
    return result
  }

  /// 이웃 칸 사이에 경계선이 없으면 같은 라벨로 묶는다. 비직사각형 병합은 상위 단계에서 거부한다.
  private static func mergeCells(
    columnEdges: [CGFloat], rowEdges: [CGFloat], lines: [Line]
  ) -> [Int] {
    let columns = columnEdges.count - 1
    let rows = rowEdges.count - 1
    var labels = Array(0..<(columns * rows))
    func merge(_ first: Int, _ second: Int) {
      let old = labels[second]
      let replacement = labels[first]
      for index in labels.indices where labels[index] == old { labels[index] = replacement }
    }
    for row in 0..<rows {
      for column in 0..<columns {
        let index = row * columns + column
        if column + 1 < columns,
          !covers(lines, vertical: true, at: columnEdges[column + 1],
                  from: rowEdges[row + 1], to: rowEdges[row]) {
          merge(index, index + 1)
        }
        if row + 1 < rows,
          !covers(lines, vertical: false, at: rowEdges[row + 1],
                  from: columnEdges[column], to: columnEdges[column + 1]) {
          merge(index, index + columns)
        }
      }
    }
    return labels
  }
}
