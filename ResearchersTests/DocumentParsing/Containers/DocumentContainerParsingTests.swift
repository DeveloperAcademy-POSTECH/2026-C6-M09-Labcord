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
    _ = try await DocumentParser.parse(input,
      options: .init(extractImages: true, performOCR: true))
    XCTAssertEqual(try parserDirectories(), before)
  }

  func testDataSliceWithNonzeroStartIndexParsesAsACompleteDocument() async throws {
    var prefixed = Data([0, 1, 2])
    prefixed.append(DocumentOfficeFixtures.word())
    let result = try await DocumentParser.parse(
      .data(
        prefixed.dropFirst(3), fileName: "sliced.docx"
      ),
      options: .init(extractImages: true, performOCR: true))
    XCTAssertTrue(result.fullText.contains("Word body marker"))
  }

  func testOOXMLDocumentsExtractBodyTablesSheetsAndSlideText() async throws {
    let word = DocumentOfficeFixtures.word()
    let excel = DocumentOfficeFixtures.excel()
    let slides = DocumentOfficeFixtures.slides()

    let wordResult = try await DocumentParser.parse(.data(word, fileName: "sample.docx"),
      options: .init(extractImages: true, performOCR: true))
    let excelResult = try await DocumentParser.parse(.data(excel, fileName: "sample.xlsx"),
      options: .init(extractImages: true, performOCR: true))
    let slideResult = try await DocumentParser.parse(.data(slides, fileName: "sample.pptx"),
      options: .init(extractImages: true, performOCR: true))

    XCTAssertTrue(wordResult.fullText.contains("Word body marker"), wordResult.fullText)
    XCTAssertTrue(
      wordResult.blocks.contains {
        $0.kind == .tableCell && $0.text == "Word cell marker"
      })
    XCTAssertEqual(excelResult.format, .xlsx)
    XCTAssertTrue(excelResult.fullText.contains("Sheet cell marker"), excelResult.fullText)
    let cell = try XCTUnwrap(excelResult.blocks.first { $0.text == "Sheet cell marker" })
    XCTAssertEqual(excelResult.blocks.filter { $0.kind == .tableCell }.count, 1)
    XCTAssertEqual(cell.location.row, 1)
    XCTAssertEqual(cell.location.column, 1)
    let body = try XCTUnwrap(wordResult.blocks.first { $0.text == "Word body marker" })
    XCTAssertEqual(body.kind, .paragraph)
    XCTAssertNil(body.location.row)
    XCTAssertNil(body.location.column)
    XCTAssertEqual(wordResult.blocks.map(\.readingOrder), Array(wordResult.blocks.indices))
    XCTAssertTrue(slideResult.fullText.contains("Slide text marker"), slideResult.fullText)
  }

  func testSpreadsheetSparseAndMergedCellKeepsOriginalAddress() async throws {
    let data = DocumentOfficeFixtures.excel(cellReference: "C4", mergedRange: "C4:D5")
    let result = try await DocumentParser.parse(.data(data, fileName: "merged.xlsx"))
    let cells = result.blocks.filter { $0.kind == .tableCell }
    XCTAssertEqual(cells.count, 1)
    let cell = try XCTUnwrap(cells.first)
    XCTAssertEqual(cell.text, "Sheet cell marker")
    XCTAssertEqual(cell.location.row, 4)
    XCTAssertEqual(cell.location.column, 3)
    XCTAssertEqual(cell.location.rowSpan, 2)
    XCTAssertEqual(cell.location.columnSpan, 2)
  }

  func testSpreadsheetCellVisitLimitPreservesPartialResult() async throws {
    let data = DocumentOfficeFixtures.excel(trailingCell: "B100001")
    let result = try await DocumentParser.parse(.data(data, fileName: "sparse.xlsx"))
    XCTAssertEqual(result.blocks.first?.kind, .table)
    XCTAssertEqual(
      result.blocks.filter { $0.kind == .tableCell }.map(\.text), ["Sheet cell marker"])
    XCTAssertTrue(result.warnings.contains {
      $0.code == .resourceLimitReached && $0.location?.row != nil
    })
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

    let result = try await DocumentParser.parse(.data(hwpx, fileName: "sample.hwpx"),
      options: .init(extractImages: true, performOCR: true))
    XCTAssertTrue(result.fullText.contains("HWPX marker"))
    XCTAssertTrue(
      result.blocks.contains {
        $0.kind == .tableCell && $0.text == "HWPX table marker"
      })
    XCTAssertTrue(result.blocks.contains { $0.kind == .imageOCR && $0.text.contains("LABCORD") })
  }
}
