import Foundation
import UIKit
import XCTest

@testable import Researchers

/// 텍스트 계열의 구조와 로컬 그림 OCR을 확인한다. 전체 텍스트는 블록에서 일관되게 만들어져야 한다.
final class DocumentParsingTests: XCTestCase {
  func testTextAndCSVKeepStructuredTextConsistent() async throws {
    let textResult = try await DocumentParser.parse(
      .data(
        Data(
          """
          첫째 줄
          Second line
          """.utf8), fileName: "notes.txt")
    )
    XCTAssertEqual(textResult.fullText, "첫째 줄\nSecond line")
    XCTAssertEqual(textResult.blocks.map(\.kind), [.paragraph, .paragraph])

    let csvResult = try await DocumentParser.parse(
      .data(
        Data(
          """
          Name,Note
          Ada,"one, two"
          """.utf8), fileName: "table.csv")
    )
    XCTAssertEqual(csvResult.format, .csv)
    XCTAssertEqual(
      csvResult.blocks.filter { $0.kind == .tableCell }.map(\.text),
      ["Name", "Note", "Ada", "one, two"])
    XCTAssertEqual(csvResult.fullText, "Name\nNote\nAda\none, two")
    XCTAssertEqual(csvResult.blocks.filter { $0.kind == .tableCell }.last?.location.column, 2)
  }

  func testJSONXMLAndMarkdownExtractStructure() async throws {
    let json = try await DocumentParser.parse(
      .data(Data("{\"experiment\":{\"temperature\":37}}".utf8), fileName: "record.json")
    )
    XCTAssertTrue(json.fullText.contains("experiment.temperature: 37"))

    let xml = try await DocumentParser.parse(
      .data(
        Data("<root><sample>Alpha</sample><value>42</value></root>".utf8), fileName: "record.xml")
    )
    XCTAssertEqual(xml.fullText, "Alpha\n42")
    XCTAssertEqual(xml.blocks.first?.location.part, "root/sample")

    let markdown = try await DocumentParser.parse(
      .data(
        Data(
          """
          # Protocol

          | Step | Value |
          | --- | --- |
          | Mix | 3 ml |
          """.utf8),
        fileName: "protocol.md")
    )
    XCTAssertEqual(markdown.blocks.first?.kind, .heading)
    XCTAssertTrue(markdown.fullText.contains("Mix"))
  }

  func testHTMLLocalImageIsOCRedWithoutNetworkAccess() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let imageURL = directory.appendingPathComponent("label.png")
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("LABCORD 123"))
    let imageData = try XCTUnwrap(UIImage(cgImage: image).pngData())
    try imageData.write(to: imageURL)
    let html =
      "<html><body><p>Sample</p><img src=\"label.png\">"
      + "<img src=\"https://example.invalid/remote.png\"></body></html>"
    let source = directory.appendingPathComponent("note.html")
    try Data(html.utf8).write(to: source)

    let result = try await DocumentParser.parse(.url(source))
    XCTAssertTrue(result.fullText.contains("Sample"))
    XCTAssertTrue(result.blocks.contains { $0.kind == .imageOCR && $0.text.contains("LABCORD") })
    XCTAssertTrue(result.warnings.contains { $0.code == .externalImageSkipped })
  }

  func testHTMLUsesDOMStructureForMalformedMarkupTablesAndLists() async throws {
    let html = """
      <html><body><h2>Study &amp; Results</h2><p>First paragraph
      <table><tr><th>Measure</th><th>Value</th></tr><tr><td>Mass</td><td>12</td></tr></table>
      <ul><li>Control</li><li>Sample</li></ul><script>hidden text</script></body></html>
      """
    let result = try await DocumentParser.parse(
      .data(Data(html.utf8), fileName: "structure.html")
    )

    XCTAssertEqual(result.blocks.first?.kind, .heading)
    XCTAssertEqual(result.blocks.first?.text, "Study & Results")
    XCTAssertTrue(result.blocks.contains { $0.kind == .tableCell && $0.text == "Measure" })
    XCTAssertTrue(result.blocks.contains { $0.kind == .tableCell && $0.text == "12" })
    XCTAssertTrue(result.blocks.contains { $0.text == "• Control" })
    XCTAssertTrue(result.blocks.contains { $0.text == "• Sample" })
    XCTAssertFalse(result.fullText.contains("hidden text"))
    XCTAssertEqual(result.blocks.map(\.readingOrder), Array(0..<result.blocks.count))
  }
}
