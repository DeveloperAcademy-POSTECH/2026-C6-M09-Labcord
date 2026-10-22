import Foundation
import XCTest

@testable import Researchers

/// 확장자나 ZIP 안의 우연한 문자열만으로 형식을 오판하지 않는지 손상·위장 컨테이너로 확인한다.
final class DocumentArchiveValidationTests: XCTestCase {
  func testFormatDetectionReadsDirectoryBeyondFirst512KiB() throws {
    let archive = DocumentArchiveFixtureBuilder.make([
      ("large.bin", Data(repeating: 0, count: 600 * 1024)),
      ("word/document.xml", Data("<document/>".utf8))
    ])

    XCTAssertEqual(try DocumentFormatDetector.detect(data: archive, fileName: nil), .docx)
  }

  func testPayloadCannotImpersonateOfficeEntry() throws {
    let archive = DocumentArchiveFixtureBuilder.make([
      ("notes.txt", Data("word/document.xml".utf8))
    ])

    XCTAssertThrowsError(
      try DocumentFormatDetector.detect(
        data: archive, fileName: "sample.docx"
      )
    ) {
      XCTAssertEqual($0 as? DocumentParsingError, .unsupportedFormat)
    }
  }

  func testDuplicateEntriesAndAbsolutePathsAreRejected() {
    for files in [
      [("same.xml", Data()), ("same.xml", Data())],
      [("C:/outside.xml", Data())],
      [("/outside.xml", Data())],
      [("folder/../outside.xml", Data())]
    ] {
      let archive = DocumentArchiveFixtureBuilder.make(files)
      XCTAssertThrowsError(try DocumentArchiveGuard.validate(archive, options: .init())) {
        XCTAssertEqual($0 as? DocumentParsingError, .malformedDocument)
      }
    }
  }

  func testArchiveEntryLimitIsAppliedDuringIdentification() {
    let archive = DocumentArchiveFixtureBuilder.make([
      ("one.xml", Data()), ("word/document.xml", Data())
    ])

    XCTAssertThrowsError(
      try DocumentFormatDetector.detect(
        data: archive, fileName: nil, options: .init(maximumArchiveEntries: 1)
      )
    ) {
      XCTAssertEqual($0 as? DocumentParsingError, .inputTooLarge)
    }
  }

  func testTruncatedDirectoryIsRejected() {
    let archive = DocumentArchiveFixtureBuilder.make([("word/document.xml", Data())])
    XCTAssertThrowsError(
      try DocumentArchiveGuard.validate(
        Data(archive.dropLast()), options: .init()
      ))
  }
}
