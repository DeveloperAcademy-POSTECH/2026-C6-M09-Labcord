import Foundation
import SwiftSoup

/// 브라우저 렌더링 없이 DOM 순서대로 제목·본문·목록·표를 추출한다.
/// 스크립트와 스타일은 실행하지 않으며 CSS로 배치된 시각적 순서는 복원하지 않는다.
nonisolated enum DocumentHTMLParser {
  static func parseHTML(_ html: String) throws -> [DocumentBlock] {
    let document = try SwiftSoup.parse(html)
    try document.select("script, style, noscript, template").remove()
    var blocks: [DocumentBlock] = []
    if let body = document.body() {
      try appendContent(body, to: &blocks)
    }
    return blocks
  }

  /// 인라인 텍스트를 모으다가 블록 요소를 만나면 먼저 내보내 DOM의 앞뒤 순서를 유지한다.
  private static func appendContent(
    _ element: Element,
    prefix: String = "",
    to blocks: inout [DocumentBlock]
  ) throws {
    var inlineText = ""
    for node in element.getChildNodes() {
      try Task.checkCancellation()
      if let text = node as? TextNode {
        inlineText += text.getWholeText()
      } else if let child = node as? Element {
        if child.tagName() == "br" {
          inlineText += "\n"
        } else if child.isBlock() {
          appendText(inlineText, prefix: prefix, to: &blocks)
          inlineText = ""
          try appendElement(child, to: &blocks)
        } else {
          inlineText += try child.text()
        }
      }
    }
    appendText(inlineText, prefix: prefix, to: &blocks)
  }

  private static func appendElement(_ element: Element, to blocks: inout [DocumentBlock]) throws {
    let tag = element.tagName()
    switch tag {
    case "table":
      try appendTable(element, to: &blocks)
    case "h1", "h2", "h3", "h4", "h5", "h6":
      appendText(try element.text(), kind: .heading, part: tag, to: &blocks)
    case "p", "pre":
      appendText(try element.text(), to: &blocks)
    case "li":
      try appendContent(element, prefix: "• ", to: &blocks)
    default:
      try appendContent(element, to: &blocks)
    }
  }

  private static func appendTable(_ table: Element, to blocks: inout [DocumentBlock]) throws {
    for (rowIndex, row) in try table.select("tr").enumerated() {
      try Task.checkCancellation()
      let cells = row.children().filter { ["td", "th"].contains($0.tagName()) }
      guard !cells.isEmpty else { continue }
      blocks.append(
        DocumentBlock(
          kind: .table,
          text: "",
          readingOrder: blocks.count,
          location: DocumentLocation(row: rowIndex + 1)
        ))
      for (columnIndex, cell) in cells.enumerated() {
        blocks.append(
          DocumentBlock(
            kind: .tableCell,
            text: try cell.text().trimmingCharacters(in: .whitespacesAndNewlines),
            readingOrder: blocks.count,
            location: DocumentLocation(row: rowIndex + 1, column: columnIndex + 1)
          ))
      }
    }
  }

  private static func appendText(
    _ text: String,
    prefix: String = "",
    kind: DocumentBlockKind = .paragraph,
    part: String? = nil,
    to blocks: inout [DocumentBlock]
  ) {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }
    blocks.append(
      DocumentBlock(
        kind: kind,
        text: prefix + value,
        readingOrder: blocks.count,
        location: DocumentLocation(part: part)
      ))
  }
}
