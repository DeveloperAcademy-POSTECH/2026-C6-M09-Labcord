import Foundation
import XCTest

@testable import Researchers

final class DocumentFormatDetectionTests: XCTestCase {
  func testUTF16WithAndWithoutBOMKeepsMixedText() throws {
    let text = "한글 English document"
    for encoding in [String.Encoding.utf16, .utf16LittleEndian, .utf16BigEndian] {
      let data = try XCTUnwrap(text.data(using: encoding))
      XCTAssertEqual(DocumentFormatDetector.decodeText(data), text)
      XCTAssertEqual(try DocumentFormatDetector.detect(data: data, fileName: "note.txt"), .txt)
    }
  }

  func testWindows1252AccentsAreNotMisreadAsUTF16() throws {
    let text = "English and português: não contabilize"
    let data = try XCTUnwrap(text.data(using: .windowsCP1252))
    XCTAssertEqual(DocumentFormatDetector.decodeText(data), text)
    XCTAssertEqual(try DocumentFormatDetector.detect(data: data, fileName: "note.txt"), .txt)
  }

  func testMarkdownStartingWithHTMLCommentKeepsHeading() async throws {
    let text = "<!-- License notice -->\n# Project heading\nBody text"
    let result = try await DocumentParser.parse(.data(Data(text.utf8), fileName: "README.md"))
    XCTAssertEqual(result.format, .markdown)
    XCTAssertTrue(result.blocks.contains { $0.kind == .heading && $0.text == "Project heading" })
  }
}
