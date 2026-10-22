import Foundation
import XCTest

@testable import Researchers

/// 인용 CSV·빈 Markdown 셀·중첩 HTML·참조 그림 실패 등 이전 경계 사례가 다시 깨지지 않는지 확인한다.
final class DocumentParsingRegressionTests: XCTestCase {
  func testCSVPreservesRowsAndQuotedFieldsWithWindowsLineEndings() async throws {
    let csv = "Name,Note\r\nAda,\"first\r\nsecond\"\r\nGrace,\"a\"\"b\"\r\n"
    let result = try await DocumentParser.parse(.data(Data(csv.utf8), fileName: "windows.csv"))
    let cells = result.blocks.filter { $0.kind == .tableCell }

    XCTAssertEqual(cells.map(\.text), ["Name", "Note", "Ada", "first\r\nsecond", "Grace", "a\"b"])
    XCTAssertEqual(cells.map { $0.location.row }, [1, 1, 2, 2, 3, 3])
  }

  func testMarkdownPreservesTablePositionAndEmptyCells() async throws {
    let markdown = """
      # Before
      Intro
      | First | Empty | Last |
      | --- | --- | --- |
      | A | | C |
      After
      """
    let result = try await DocumentParser.parse(.data(Data(markdown.utf8), fileName: "table.md"))
    let cells = result.blocks.filter { $0.kind == .tableCell }

    XCTAssertEqual(cells.map(\.text), ["First", "Empty", "Last", "A", "", "C"])
    XCTAssertEqual(cells.last?.location.column, 3)
    XCTAssertEqual(result.fullText, "Before\nIntro\nFirst\nEmpty\nLast\nA\nC\nAfter")
    XCTAssertEqual(result.blocks.map(\.readingOrder), Array(result.blocks.indices))
  }

  func testHTMLKeepsDirectTextInlineMarkupAndNestedLists() async throws {
    let html = """
      <div>Before <strong>bold</strong> after</div>
      <ul><li>Parent <em>item</em><ul><li>Child</li></ul></li></ul>
      <p>End</p>
      """
    let result = try await DocumentParser.parse(.data(Data(html.utf8), fileName: "fragment.html"))

    XCTAssertEqual(result.format, .html)
    XCTAssertEqual(result.fullText, "Before bold after\n• Parent item\n• Child\nEnd")
  }

  func testReferencedImageFailureKeepsExtractedText() async throws {
    let html = "<html><body><p>Kept</p><img src=\"data:image/png;base64,AAAA\"></body></html>"
    let result = try await DocumentParser.parse(.data(Data(html.utf8), fileName: "partial.html"))

    XCTAssertEqual(result.fullText, "Kept")
    XCTAssertTrue(
      result.warnings.contains {
        $0.code == .imageOCRFailed && $0.location?.part == "data:image/png;base64,AAAA"
      })
  }

  func testResultNormalizesDuplicateOrdersWithoutReorderingTies() {
    let blocks = [
      DocumentBlock(kind: .paragraph, text: "Late", readingOrder: 20),
      DocumentBlock(kind: .paragraph, text: "First", readingOrder: 1),
      DocumentBlock(kind: .imageOCR, text: "Second", readingOrder: 1)
    ]
    let result = DocumentParseResult(format: .html, blocks: blocks, warnings: [])

    XCTAssertEqual(result.blocks.map(\.text), ["First", "Second", "Late"])
    XCTAssertEqual(result.blocks.map(\.readingOrder), [0, 1, 2])
    XCTAssertEqual(result.fullText, "First\nSecond\nLate")
  }
}
