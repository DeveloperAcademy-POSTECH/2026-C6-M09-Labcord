import CryptoKit
import Foundation
import XCTest

@testable import Researchers

/// 20형식마다 외부 원본 3개를 해시·출처·부분 정답과 대조한다. 생성 샘플만으로 실제 형식 호환성을 주장하지 않는다.
final class DocumentRealWorldCorpusTests: XCTestCase {
  func testCorpusCoversEveryFileFormatWithThreeDistinctFiles() throws {
    let fixtures = try loadManifest()
    let formats = Set(DocumentFormat.allCases.filter { $0 != .image }.map(\.rawValue))
    XCTAssertEqual(Set(fixtures.map(\.format)), formats)
    XCTAssertEqual(Set(fixtures.map(\.id)).count, fixtures.count)
    XCTAssertEqual(Set(fixtures.map(\.filename)).count, fixtures.count)
    for format in formats.sorted() {
      let entries = fixtures.filter { $0.format == format }
      XCTAssertEqual(entries.count, 3, format)
      XCTAssertEqual(Set(entries.map(\.sha256)).count, 3, format)
      for fixture in entries {
        XCTAssertTrue(fixture.sourceURL.hasPrefix("https://"), fixture.id)
        XCTAssertTrue(fixture.licenseEvidenceURL.hasPrefix("https://"), fixture.id)
        XCTAssertFalse(fixture.license.isEmpty, fixture.id)
      }
    }
  }

  func testTXT() async throws { try await verify(.txt) }
  func testCSV() async throws { try await verify(.csv) }
  func testJSON() async throws { try await verify(.json) }
  func testXML() async throws { try await verify(.xml) }
  func testJPEG() async throws { try await verify(.jpeg) }
  func testPNG() async throws { try await verify(.png) }
  func testHEIC() async throws { try await verify(.heic) }
  func testTIFF() async throws { try await verify(.tiff) }
  func testPDF() async throws { try await verify(.pdf) }
  func testDOCX() async throws { try await verify(.docx) }
  func testXLSX() async throws { try await verify(.xlsx) }
  func testPPTX() async throws { try await verify(.pptx) }
  func testHWP() async throws { try await verify(.hwp) }
  func testHWPX() async throws { try await verify(.hwpx) }
  func testRTF() async throws { try await verify(.rtf) }
  func testHTML() async throws { try await verify(.html) }
  func testMarkdown() async throws { try await verify(.markdown) }
  func testDOC() async throws { try await verify(.doc) }
  func testXLS() async throws { try await verify(.xls) }
  func testPPT() async throws { try await verify(.ppt) }

  private func verify(_ format: DocumentFormat) async throws {
    let fixtures = try loadManifest().filter { $0.format == format.rawValue }
    XCTAssertEqual(fixtures.count, 3, format.rawValue)
    for fixture in fixtures {
      do {
        let url = try resourceURL(fixture.filename, subdirectory: "RealWorld/\(fixture.format)")
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, fixture.sha256, fixture.id)
        let start = Date()
        let result = try await DocumentParser.parse(.data(data, fileName: fixture.filename))
        let elapsed = Date().timeIntervalSince(start)
        check(result, fixture: fixture, format: format)
        try DocumentGoldenAssertions.verify(result, id: fixture.id, sha256: digest)
        record(result, fixture: fixture, inputBytes: data.count, seconds: elapsed)
      } catch {
        let category = (error as? DocumentParsingError).map { String(describing: $0) }
          ?? String(reflecting: type(of: error))
        XCTFail("\(fixture.id): \(category)")
      }
    }
  }

  private func check(
    _ result: DocumentParseResult,
    fixture: Fixture,
    format: DocumentFormat
  ) {
    XCTAssertEqual(result.format, format, fixture.id)
    XCTAssertEqual(result.blocks.map(\.readingOrder), Array(result.blocks.indices), fixture.id)
    let textKinds: [DocumentBlockKind] = [.paragraph, .heading, .tableCell, .imageOCR]
    let blockText = result.blocks.filter { textKinds.contains($0.kind) }
      .map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    XCTAssertTrue(result.fullText == blockText, fixture.id)
    XCTAssertGreaterThanOrEqual(result.fullText.count, fixture.minimumTextLength, fixture.id)
    let normalized = normalize(result.fullText)
    for phrase in fixture.expectedText {
      XCTAssertTrue(
        normalized.contains(normalize(phrase)), "\(fixture.id): missing expected phrase")
    }
    XCTAssertGreaterThanOrEqual(
      result.blocks.filter { $0.kind == .tableCell }.count, fixture.minimumTableCells, fixture.id)
    XCTAssertGreaterThanOrEqual(result.images.count, fixture.minimumImages, fixture.id)
    for code in fixture.forbiddenWarningCodes ?? [] {
      XCTAssertFalse(result.warnings.contains { $0.code.rawValue == code }, fixture.id)
    }
    for page in fixture.expectedOCRPages ?? [] {
      XCTAssertTrue(result.blocks.contains {
        $0.kind == .imageOCR && $0.location.page == page
      }, "\(fixture.id): missing OCR page \(page)")
    }
    for block in result.blocks {
      if let bounds = block.location.bounds {
        XCTAssertTrue(bounds.minX.isFinite && bounds.minY.isFinite, fixture.id)
        XCTAssertTrue(bounds.width.isFinite && bounds.height.isFinite, fixture.id)
        XCTAssertGreaterThanOrEqual(bounds.width, 0, fixture.id)
        XCTAssertGreaterThanOrEqual(bounds.height, 0, fixture.id)
      }
    }
  }

  private func record(
    _ result: DocumentParseResult,
    fixture: Fixture,
    inputBytes: Int,
    seconds: TimeInterval
  ) {
    let metrics: [String: Any] = [
      "id": fixture.id, "format": fixture.format, "inputBytes": inputBytes,
      "seconds": seconds, "textCharacters": result.fullText.count,
      "blocks": result.blocks.count, "images": result.images.count,
      "warningCodes": result.warnings.map { $0.code.rawValue }
    ]
    if let data = try? JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys]) {
      let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
      attachment.name = "\(fixture.id)-metrics"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }

  private func normalize(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
  }

  private func resourceURL(
    _ filename: String, subdirectory: String = "RealWorld"
  ) throws -> URL {
    let name = filename as NSString
    return try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: name.deletingPathExtension, withExtension: name.pathExtension,
      subdirectory: subdirectory))
  }

  private func loadManifest() throws -> [Fixture] {
    let url = try resourceURL("RealWorldManifest.json")
    return try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
  }

  private struct Fixture: Decodable {
    let id: String
    let filename: String
    let format: String
    let sha256: String
    let sourceURL: String
    let license: String
    let licenseEvidenceURL: String
    let expectedText: [String]
    let minimumTextLength: Int
    let minimumTableCells: Int
    let minimumImages: Int
    let expectedOCRPages: [Int]?
    let forbiddenWarningCodes: [String]?
  }
}
