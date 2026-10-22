import Foundation
import XCTest

@testable import Researchers

/// 인용 CSV·빈 Markdown 셀·중첩 HTML·참조 그림 실패 등 이전 경계 사례가 다시 깨지지 않는지 확인한다.
final class DocumentParsingRegressionTests: XCTestCase {
  func testCSVPreservesRowsAndQuotedFieldsWithWindowsLineEndings() async throws {
    let csv = "Name,Note\r\nAda,\"first\r\nsecond\"\r\nGrace,\"a\"\"b\"\r\n"
    let result = try await DocumentParser.parse(.data(Data(csv.utf8), fileName: "windows.csv"),
      options: .init(extractImages: true, performOCR: true))
    let cells = result.blocks.filter { $0.kind == .tableCell }

    XCTAssertEqual(cells.map(\.text), ["Name", "Note", "Ada", "first\r\nsecond", "Grace", "a\"b"])
    XCTAssertEqual(cells.map { $0.location.row }, [1, 1, 2, 2, 3, 3])
  }

  func testCSVIteratorPreservesUnicodeEmptyCellsAndFinalQuotedField() async throws {
    let note = "e\u{301} 👩🏽‍🔬\r\n한글"
    let csv = "id,note,last\r\n1,\"\(note)\",\r\n2,\"a\"\"b\",\"\""
    let result = try await DocumentParser.parse(.data(Data(csv.utf8), fileName: "unicode.csv"),
      options: .init(extractImages: true, performOCR: true))
    let cells = result.blocks.filter { $0.kind == .tableCell }

    XCTAssertEqual(cells.map(\.text), ["id", "note", "last", "1", note, "", "2", "a\"b", ""])
    XCTAssertEqual(cells.map { $0.location.row }, [1, 1, 1, 2, 2, 2, 3, 3, 3])
    XCTAssertEqual(cells.map { $0.location.column }, [1, 2, 3, 1, 2, 3, 1, 2, 3])
    XCTAssertEqual(result.fullText, "id\nnote\nlast\n1\n\(note)\n2\na\"b")
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
    let result = try await DocumentParser.parse(.data(Data(markdown.utf8), fileName: "table.md"),
      options: .init(extractImages: true, performOCR: true))
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
    let result = try await DocumentParser.parse(.data(Data(html.utf8), fileName: "fragment.html"),
      options: .init(extractImages: true, performOCR: true))

    XCTAssertEqual(result.format, .html)
    XCTAssertEqual(result.fullText, "Before bold after\n• Parent item\n• Child\nEnd")
  }

  func testReferencedImageFailureKeepsExtractedText() async throws {
    let html = "<html><body><p>Kept</p><img src=\"data:image/png;base64,AAAA\"></body></html>"
    let result = try await DocumentParser.parse(.data(Data(html.utf8), fileName: "partial.html"),
      options: .init(extractImages: true, performOCR: true))

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

  func testXMLFlushKeepsMixedContentPathsWithoutWhitespaceBlocks() async throws {
    let xml = "<root> \n <item>Alpha<child>Beta</child>Gamma</item> \n <empty/>Tail</root>"
    let result = try await DocumentParser.parse(.data(Data(xml.utf8), fileName: "mixed.xml"),
      options: .init(extractImages: true, performOCR: true))

    XCTAssertEqual(result.fullText, "Alpha\nBeta\nGamma\nTail")
    XCTAssertEqual(result.blocks.map { $0.location.part },
                   ["root/item", "root/item/child", "root/item", "root"])
    XCTAssertTrue(result.blocks.allSatisfy { !$0.text.isEmpty })
  }

  func testOrderedResultKeepsTiesAndExcludesStructuralText() {
    let blocks = [
      DocumentBlock(kind: .table, text: "structure", readingOrder: 0),
      DocumentBlock(kind: .paragraph, text: "First", readingOrder: 4),
      DocumentBlock(kind: .image, text: "description", readingOrder: 4),
      DocumentBlock(kind: .imageOCR, text: "Second", readingOrder: 4),
      DocumentBlock(kind: .tableCell, text: "Third", readingOrder: 10),
      DocumentBlock(kind: .heading, text: "", readingOrder: 12)
    ]
    let result = DocumentParseResult(format: .csv, blocks: blocks, warnings: [])

    XCTAssertEqual(result.blocks.map(\.text), blocks.map(\.text))
    XCTAssertEqual(result.blocks.map(\.readingOrder), Array(blocks.indices))
    XCTAssertEqual(result.fullText, "First\nSecond\nThird")
    XCTAssertTrue(DocumentParseResult(format: .txt, blocks: [], warnings: []).fullText.isEmpty)
  }

  /// 손상 참조도 시도 수에 포함한다. HTML과 Markdown 모두 동일한 한도를 적용한다.
  func testReferenceLimitCountsFailuresAndKeepsTextInBothMarkupFormats() async throws {
    let references = ["AAAA", "AAAB", "AAAC"].map { "data:image/png;base64," + $0 }
    let html = "<html><body><p>Kept</p>"
      + references.map { "<img src=\"\($0)\">" }.joined() + "</body></html>"
    let markdown = "Kept\n" + references.map { "![](\($0))" }.joined(separator: "\n")
    for (text, filename) in [(html, "limit.html"), (markdown, "limit.md")] {
      let result = try await DocumentParser.parse(
        .data(Data(text.utf8), fileName: filename), options: .init(
          extractImages: true, performOCR: true,
          maximumEmbeddedImages: 1))
      XCTAssertEqual(result.fullText, "Kept")
      XCTAssertEqual(result.warnings.filter { $0.code == .imageOCRFailed }.count, 1)
      let limits = result.warnings.filter { $0.code == .resourceLimitReached }
      XCTAssertEqual(limits.count, 1)
      XCTAssertTrue(limits.first?.location?.part == references[1])
      XCTAssertFalse(result.warnings.contains { $0.location?.part == references[2] })
    }
  }

  func testReferenceLimitPreservesEarlierOCRAtExactBoundary() async throws {
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("LIMIT OCR 123"))
    let png = try XCTUnwrap(DocumentImageEncoder.png(image))
    let reference = "data:image/png;base64," + png.base64EncodedString()
    let html = "<html><body><p>Kept</p><img src=\"\(reference)\">"
      + "<img src=\"data:image/png;base64,AAAA\"></body></html>"
    let result = try await DocumentParser.parse(
      .data(Data(html.utf8), fileName: "boundary.html"),
      options: .init(
        extractImages: true, performOCR: true,
        maximumEmbeddedImages: 2))

    XCTAssertTrue(result.fullText.hasPrefix("Kept\n"))
    XCTAssertTrue(result.fullText.contains("LIMIT OCR 123"))
    XCTAssertTrue(result.blocks.contains { $0.kind == .imageOCR })
    XCTAssertEqual(result.warnings.filter { $0.code == .imageOCRFailed }.count, 1)
    XCTAssertFalse(result.warnings.contains { $0.code == .resourceLimitReached })
  }

  /// 공개 입력 한도에서 먼저 거부되지 않도록 내부 참조 읽기의 바이트 경계를 직접 검사한다.
  func testBase64ByteLimitHandlesAllPaddingLengthsAndWhitespace() {
    for count in 1...12 {
      let encoded = Data(repeating: 1, count: count).base64EncodedString()
      let reference = "data:image/png;base64,\n" + encoded + " \t"
      XCTAssertThrowsError(try DocumentReferencedImageParser.parse(
        reference, baseDirectory: nil, options: .init(
          extractImages: true, performOCR: true,
          maximumInputBytes: count))) {
        // 바이트 한도는 통과하지만 PNG가 아닌 의도적인 손상 샘플이다.
        XCTAssertEqual($0 as? DocumentParsingError, .malformedDocument)
      }
      if count > 1 {
        XCTAssertThrowsError(try DocumentReferencedImageParser.parse(
          reference, baseDirectory: nil, options: .init(
            extractImages: true, performOCR: true,
            maximumInputBytes: count - 1))) {
          XCTAssertEqual($0 as? DocumentParsingError, .inputTooLarge)
        }
      }
    }
  }

  func testBase64RejectsOversizedPayloadBeforeDecoding() {
    let reference = "data:image/png;base64," + String(repeating: "!", count: 16)
    XCTAssertThrowsError(try DocumentReferencedImageParser.parse(
      reference, baseDirectory: nil, options: .init(
        extractImages: true, performOCR: true,
        maximumInputBytes: 1))) {
      // 디코딩을 먼저 했다면 malformedDocument가 된다. 크기 검사 순서까지 확인한다.
      XCTAssertEqual($0 as? DocumentParsingError, .inputTooLarge)
    }
  }

  func testLocalReferenceByteLimitReturnsWarningAndPreservesText() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("DocumentReferenceTest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data(repeating: 0, count: 512).write(to: directory.appendingPathComponent("large.png"))
    let html = "<html><body><p>Kept</p><img src=\"large.png\"></body></html>"
    let url = directory.appendingPathComponent("local.html")
    try Data(html.utf8).write(to: url)
    let result = try await DocumentParser.parse(.url(url), options: .init(
      extractImages: true, performOCR: true,
      maximumInputBytes: 128))

    XCTAssertEqual(result.fullText, "Kept")
    XCTAssertTrue(result.warnings.contains {
      $0.code == .resourceLimitReached && $0.location?.part == "large.png"
    })
    XCTAssertFalse(result.warnings.contains { $0.code == .imageOCRFailed })
  }

  func testReferencedImagePixelLimitPreservesText() async throws {
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("PIXEL LIMIT"))
    let png = try XCTUnwrap(DocumentImageEncoder.png(image))
    let reference = "data:image/png;base64," + png.base64EncodedString()
    let html = "<html><body><p>Kept</p><img src=\"\(reference)\"></body></html>"
    let result = try await DocumentParser.parse(
      .data(Data(html.utf8), fileName: "pixels.html"), options: .init(
        extractImages: true, performOCR: true,
        maximumImagePixels: 1))

    XCTAssertEqual(result.fullText, "Kept")
    XCTAssertTrue(result.warnings.contains {
      $0.code == .resourceLimitReached && $0.location?.part == reference
    })
    XCTAssertFalse(result.warnings.contains { $0.code == .imageOCRFailed })
  }
}
