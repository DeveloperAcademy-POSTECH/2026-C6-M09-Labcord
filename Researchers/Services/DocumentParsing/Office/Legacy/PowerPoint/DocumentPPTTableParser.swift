import CoreGraphics
import Foundation

/// 구형 PPT의 그룹 도형 중 사각 영역을 채우는 텍스트 도형을 표 후보로 읽는다.
/// 도형의 앵커로 행·열을 추론하며 다른 본문 요소와의 인라인 순서는 별도로 보장하지 않는다.
nonisolated enum DocumentPPTTableParser {
  private struct Cell {
    let text: String
    let bounds: CGRect
  }

  static func parse(_ streams: [String: Data]) throws -> [DocumentBlock] {
    guard let document = streams["PowerPoint Document"], let user = streams["Current User"] else {
      return []
    }
    let records = DocumentPPTRecords(reader: DocumentBinaryReader(data: document))
    var blocks: [DocumentBlock] = []
    for (slideIndex, slide) in try records.liveSlides(currentUser: user).enumerated() {
      let groups = try records.descendants(of: slide, type: 0xF003)
      for (tableIndex, group) in groups.enumerated() {
        let shapes = try records.children(of: group).filter { $0.type == 0xF004 }
        let cells = try shapes.compactMap { try cell($0, records: records) }
        guard cells.count >= 2 else { continue }
        let bounds = cells.reduce(CGRect.null) { $0.union($1.bounds) }
        let area = cells.reduce(CGFloat(0)) { $0 + $1.bounds.width * $1.bounds.height }
        guard area > 0, abs(bounds.width * bounds.height - area) / area < 0.03 else { continue }
        let rows = distinct(cells.map { $0.bounds.minY })
        let columns = distinct(cells.map { $0.bounds.minX })
        let part = "slide[\(slideIndex + 1)]/table[\(tableIndex)]"
        blocks.append(
          DocumentBlock(
            kind: .table, text: "", readingOrder: blocks.count,
            location: DocumentLocation(part: part)))
        for cell in cells.sorted(by: {
          if $0.bounds.minY != $1.bounds.minY { return $0.bounds.minY < $1.bounds.minY }
          return $0.bounds.minX < $1.bounds.minX
        }) {
          let row = (rows.firstIndex { abs($0 - cell.bounds.minY) < 1 } ?? 0) + 1
          let column = (columns.firstIndex { abs($0 - cell.bounds.minX) < 1 } ?? 0) + 1
          blocks.append(
            DocumentBlock(
              kind: .tableCell, text: cell.text, readingOrder: blocks.count,
              location: DocumentLocation(part: part, row: row, column: column)))
        }
      }
    }
    return blocks
  }

  private static func distinct(_ values: [CGFloat]) -> [CGFloat] {
    values.sorted().reduce(into: []) { output, value in
      if let last = output.last, abs(last - value) < 1 { return }
      output.append(value)
    }
  }

  /// 도형 앵커와 텍스트 atom을 함께 읽어 표 셀 후보를 만든다. 글꼴·장식은 공통 텍스트에 포함하지 않는다.
  private static func cell(
    _ shape: DocumentPPTRecords.Record, records: DocumentPPTRecords
  ) throws -> Cell? {
    let children = try records.children(of: shape)
    guard let anchor = children.first(where: { $0.type == 0xF00F }),
      anchor.end - anchor.start >= 16
    else { return nil }
    var coordinates: [CGFloat] = []
    for index in 0..<4 {
      guard let value = records.reader.uint32(anchor.start + index * 4) else { return nil }
      coordinates.append(CGFloat(Int32(bitPattern: UInt32(value))))
    }
    let bounds = CGRect(
      x: coordinates[0], y: coordinates[1],
      width: coordinates[2] - coordinates[0], height: coordinates[3] - coordinates[1])
    guard bounds.width > 0, bounds.height > 0 else { return nil }
    var text: [String] = []
    for type in [4000, 4008] {
      for atom in try records.descendants(of: shape, type: type) {
        guard let data = records.reader.slice(atom.start, count: atom.end - atom.start),
          let value = String(
            data: data, encoding: type == 4000 ? .utf16LittleEndian : .windowsCP1252)
        else { continue }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty, !text.contains(cleaned) { text.append(cleaned) }
      }
    }
    guard !text.isEmpty else { return nil }
    return Cell(text: text.joined(separator: "\n"), bounds: bounds)
  }
}
