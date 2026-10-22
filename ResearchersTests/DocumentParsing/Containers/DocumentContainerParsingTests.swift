import Foundation
import UIKit
import XCTest

@testable import Researchers

/// 컨테이너 형식의 본문·표·그림과 임시 파일 수명을 확인한다. 바이트 슬라이스 입력도 원본과 같이 읽혀야 한다.
final class DocumentContainerParsingTests: XCTestCase {
  func testOfficeParsingRemovesItsTemporaryDirectory() async throws {
    let directory = FileManager.default.temporaryDirectory
    func parserDirectories() throws -> Set<String> {
      Set(
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
          .filter { $0.hasPrefix("DocumentParsing-") })
    }
    let before = try parserDirectories()
    let input = DocumentInput.data(DocumentOfficeFixtures.word(), fileName: "clean.docx")
    _ = try await DocumentParser.parse(input)
    XCTAssertEqual(try parserDirectories(), before)
  }

  func testDataSliceWithNonzeroStartIndexParsesAsACompleteDocument() async throws {
    var prefixed = Data([0, 1, 2])
    prefixed.append(DocumentOfficeFixtures.word())
    let result = try await DocumentParser.parse(
      .data(
        prefixed.dropFirst(3), fileName: "sliced.docx"
      ))
    XCTAssertTrue(result.fullText.contains("Word body marker"))
  }

  func testOOXMLDocumentsExtractBodyTablesSheetsAndSlideText() async throws {
    let word = DocumentOfficeFixtures.word()
    let excel = DocumentOfficeFixtures.excel()
    let slides = DocumentOfficeFixtures.slides()

    let wordResult = try await DocumentParser.parse(.data(word, fileName: "sample.docx"))
    let excelResult = try await DocumentParser.parse(.data(excel, fileName: "sample.xlsx"))
    let slideResult = try await DocumentParser.parse(.data(slides, fileName: "sample.pptx"))

    XCTAssertTrue(wordResult.fullText.contains("Word body marker"), wordResult.fullText)
    XCTAssertTrue(
      wordResult.blocks.contains {
        $0.kind == .tableCell && $0.text == "Word cell marker"
      })
    XCTAssertEqual(excelResult.format, .xlsx)
    XCTAssertTrue(excelResult.fullText.contains("Sheet cell marker"), excelResult.fullText)
    XCTAssertTrue(excelResult.blocks.contains { $0.kind == .tableCell })
    XCTAssertTrue(slideResult.fullText.contains("Slide text marker"), slideResult.fullText)
  }

  func testArchiveGuardRejectsTraversalAndExpandedSizeOverLimit() throws {
    let escaped = DocumentArchiveFixtureBuilder.make([("../outside.txt", Data("x".utf8))])
    XCTAssertThrowsError(try DocumentArchiveGuard.validate(escaped, options: .init()))

    let large = DocumentArchiveFixtureBuilder.make([("large.bin", Data(repeating: 1, count: 32))])
    XCTAssertThrowsError(
      try DocumentArchiveGuard.validate(large, options: .init(maximumExpandedBytes: 16))
    ) { error in
      XCTAssertEqual(error as? DocumentParsingError, .inputTooLarge)
    }
  }

  func testHWPXExtractsParagraphTableAndEmbeddedImageOCR() async throws {
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("LABCORD 123"))
    let imageData = try XCTUnwrap(UIImage(cgImage: image).pngData())
    let hwpx = DocumentHWPXFixture.make(imageData: imageData)

    let result = try await DocumentParser.parse(.data(hwpx, fileName: "sample.hwpx"))
    XCTAssertTrue(result.fullText.contains("HWPX marker"))
    XCTAssertTrue(
      result.blocks.contains {
        $0.kind == .tableCell && $0.text == "HWPX table marker"
      })
    XCTAssertTrue(result.blocks.contains { $0.kind == .imageOCR && $0.text.contains("LABCORD") })
  }
}
