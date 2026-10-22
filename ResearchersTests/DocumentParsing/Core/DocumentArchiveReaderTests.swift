import Foundation
import XCTest

@testable import Researchers

/// ZIP 헤더·CRC·실제 해제량과 HWPX XML의 엔티티·ID 충돌을 검사한다. 위험 입력은 결과 생성 전에 거부해야 한다.
final class DocumentArchiveReaderTests: XCTestCase {
  func testStoredXMLIsReadWithChecksumAndNonXMLIsExcluded() throws {
    let data = DocumentArchiveFixtureBuilder.make([
      ("Contents/section0.xml", Data("<section/>".utf8)),
      ("image.png", Data([1, 2, 3]))
    ])
    let entries = try DocumentArchiveReader.xmlEntries(data, options: .init())
    XCTAssertEqual(entries.count, 1)
    XCTAssertEqual(entries.first?.0, "Contents/section0.xml")
    XCTAssertEqual(entries.first?.1, Data("<section/>".utf8))
  }

  func testWrongCRCAndLocalFilenameAreRejected() throws {
    let original = DocumentArchiveFixtureBuilder.make([("test.xml", Data("<a/>".utf8))])
    var wrongCRC = original
    wrongCRC[30 + "test.xml".utf8.count] ^= 1
    XCTAssertThrowsError(try DocumentArchiveReader.xmlEntries(wrongCRC, options: .init()))
    var wrongName = original
    wrongName[30] = UInt8(ascii: "X")
    XCTAssertThrowsError(try DocumentArchiveReader.xmlEntries(wrongName, options: .init()))
  }

  func testDeflateCannotExpandPastDeclaredSize() throws {
    let data = try XCTUnwrap(Data(base64Encoded:
      "UEsDBBQAAAAIAKNxVV1tLrDKEQAAAO8DAAAIAAAAdGVzdC54bWyzqbBzHAWjYBQMe2CjX2EHAFBL" +
      "AQIUAxQAAAAIAKNxVV1tLrDKEQAAAO8DAAAIAAAAAAAAAAAAAACAAQAAAAB0ZXN0LnhtbFBLBQYA" +
      "AAAAAQABADYAAAA3AAAAAAA="))
    let expanded = try DocumentArchiveReader.xmlEntries(data, options: .init())
    XCTAssertEqual(expanded.first?.1.count, 1007)
    var forged = data
    let directory = try DocumentArchiveGuard.readDirectory(data)
    forged.replaceSubrange((directory.start + 24)..<(directory.start + 28), with: [1, 0, 0, 0])
    XCTAssertThrowsError(try DocumentArchiveReader.xmlEntries(forged, options: .init())) {
      XCTAssertEqual($0 as? DocumentParsingError, .inputTooLarge)
    }
  }

  func testDescriptionReaderRejectsEntityDeclarations() {
    let xml = """
      <!DOCTYPE x [<!ENTITY external SYSTEM "file:///etc/passwd">]>
      <hp:pic xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" id="1">
      <hp:shapeComment>&external;</hp:shapeComment></hp:pic>
      """
    let data = DocumentArchiveFixtureBuilder.make([("section.xml", Data(xml.utf8))])
    XCTAssertThrowsError(try DocumentHWPXDescriptions.read(data, options: .init()))
  }

  func testDescriptionsUseNamespaceAndRejectConflictingIDs() throws {
    let namespace = "http://www.hancom.co.kr/hwpml/2011/paragraph"
    let xml = """
      <root xmlns:hp="\(namespace)" xmlns:foreign="urn:foreign">
      <hp:pic id="1"><hp:shapeComment>한글 caption</hp:shapeComment></hp:pic>
      <foreign:pic id="2"><foreign:shapeComment>ignored</foreign:shapeComment></foreign:pic>
      </root>
      """
    let data = DocumentArchiveFixtureBuilder.make([("section.xml", Data(xml.utf8))])
    XCTAssertEqual(try DocumentHWPXDescriptions.read(data, options: .init()), [1: "한글 caption"])
    let conflict = """
      <root xmlns:hp="\(namespace)">
      <hp:pic id="1"><hp:shapeComment>first</hp:shapeComment></hp:pic>
      <hp:pic id="1"><hp:shapeComment>second</hp:shapeComment></hp:pic>
      </root>
      """
    let conflicting = DocumentArchiveFixtureBuilder.make([("section.xml", Data(conflict.utf8))])
    XCTAssertThrowsError(try DocumentHWPXDescriptions.read(conflicting, options: .init()))
  }

  func testExpandedLimitAndCancellationAreEnforced() async throws {
    let data = DocumentArchiveFixtureBuilder.make([("test.xml", Data(repeating: 65, count: 100))])
    XCTAssertThrowsError(try DocumentArchiveReader.xmlEntries(
      data, options: .init(maximumExpandedBytes: 99))) {
      XCTAssertEqual($0 as? DocumentParsingError, .inputTooLarge)
    }
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try DocumentArchiveReader.xmlEntries(data, options: .init())
    }
    do {
      _ = try await task.value
      XCTFail("Cancelled archive read completed")
    } catch { XCTAssertTrue(error is CancellationError) }
  }
}
