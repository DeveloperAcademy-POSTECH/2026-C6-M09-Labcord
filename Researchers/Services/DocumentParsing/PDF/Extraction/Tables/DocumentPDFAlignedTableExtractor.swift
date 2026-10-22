import CoreGraphics
import Foundation
import PDFKit

/// 선이 없는 PDF에서 반복된 문자 정렬을 표 후보로 추론한다.
/// 같은 열이 3행 이상 이어져야 채택하며 확정된 표 구조가 아니라는 경고를 함께 반환한다.
nonisolated enum DocumentPDFAlignedTableExtractor {
  static func extract(
    page: PDFPage, pageIndex: Int, space: DocumentPDFPageSpace
  ) throws -> DocumentPDFTableExtractor.Result {
    guard page.numberOfCharacters <= 100_000 else {
      return .init(warnings: [
        DocumentWarning(
          code: .resourceLimitReached,
          message: "PDF character layout exceeded the inspection limit.",
          location: DocumentLocation(page: pageIndex + 1))
      ])
    }
    let rows = try textRows(page).map(runs).filter { (2...20).contains($0.count) }
    var result = DocumentPDFTableExtractor.Result()
    var index = 0
    while index < rows.count {
      var end = index + 1
      while end < rows.count, aligned(rows[index], rows[end - 1], rows[end]) { end += 1 }
      if end - index >= 3 {
        append(
          rows: Array(rows[index..<end]), page: page, pageIndex: pageIndex,
          space: space, to: &result)
      }
      index = end
    }
    return result
  }

  private static func textRows(_ page: PDFPage) throws -> [[CGRect]] {
    var glyphs: [CGRect] = []
    // PDFKit 문자열의 합성 줄바꿈과 glyph 인덱스는 일치하지 않을 수 있습니다.
    for index in 0..<page.numberOfCharacters {
      if index % 256 == 0 { try Task.checkCancellation() }
      let bounds = page.characterBounds(at: index)
      if !bounds.isNull, !bounds.isEmpty, bounds.width.isFinite, bounds.height.isFinite,
        bounds.width <= bounds.height * 3 {
        glyphs.append(bounds)
      }
    }
    glyphs.sort {
      if $0.midY != $1.midY { return $0.midY > $1.midY }
      return $0.minX < $1.minX
    }
    var rows: [[CGRect]] = []
    for glyph in glyphs {
      if let last = rows.last?.first,
        abs(last.midY - glyph.midY) < max(2, max(last.height, glyph.height) * 0.6) {
        rows[rows.count - 1].append(glyph)
      } else {
        rows.append([glyph])
      }
    }
    return rows
  }

  private static func runs(_ glyphs: [CGRect]) -> [CGRect] {
    var output: [CGRect] = []
    for glyph in glyphs.sorted(by: { $0.minX < $1.minX }) {
      if let last = output.last, glyph.minX - last.maxX < max(12, glyph.height * 1.5) {
        output[output.count - 1] = last.union(glyph)
      } else {
        output.append(glyph)
      }
    }
    return output
  }

  private static func aligned(
    _ first: [CGRect], _ previous: [CGRect], _ current: [CGRect]
  ) -> Bool {
    guard first.count == current.count, let last = previous.first, let next = current.first,
      last.minY - next.maxY <= max(last.height, next.height) * 2.5
    else { return false }
    return zip(first, current).allSatisfy { abs($0.minX - $1.minX) < 3 }
  }

  private static func append(
    rows: [[CGRect]], page: PDFPage, pageIndex: Int, space: DocumentPDFPageSpace,
    to result: inout DocumentPDFTableExtractor.Result
  ) {
    let bounds = rows.flatMap { $0 }.reduce(CGRect.null) { $0.union($1) }
    let part = "aligned-table[\(result.blocks.count)]"
    let tableLocation = DocumentLocation(
      part: part, page: pageIndex + 1,
      bounds: space.normalized(bounds))
    result.blocks.append(
      DocumentBlock(
        kind: .table, text: "", readingOrder: 0,
        location: tableLocation))
    for (rowIndex, row) in rows.enumerated() {
      for (columnIndex, rect) in row.enumerated() {
        let text = (page.selection(for: rect.insetBy(dx: -0.1, dy: -0.1))?.string ?? "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        result.blocks.appendBlock(
          .tableCell, text: text,
          location: DocumentLocation(
            part: part, page: pageIndex + 1, row: rowIndex + 1, column: columnIndex + 1,
            bounds: space.normalized(rect)))
      }
    }
    result.warnings.append(
      DocumentWarning(
        code: .uncertainReadingOrder,
        message: "A borderless PDF table was inferred from repeated text alignment.",
        location: tableLocation))
  }
}
