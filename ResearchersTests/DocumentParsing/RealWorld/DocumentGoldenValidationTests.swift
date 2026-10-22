import Foundation
import XCTest

@testable import Researchers

/// 부분 정답 목록이 코퍼스와 맞는지, 텍스트·셀 순서·그림 누락을 실제로 검출하는지 확인한다.
final class DocumentGoldenValidationTests: XCTestCase {
  func testGoldenIDsCoverExactlyTheCorpus() throws {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: "RealWorldManifest", withExtension: "json", subdirectory: "RealWorld"))
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
      as? [[String: Any]]
    let ids = try XCTUnwrap(manifest).compactMap { $0["id"] as? String }
    let goldens = try DocumentGoldenAssertions.load()
    XCTAssertEqual(Set(ids), Set(goldens.map(\.id)))
    XCTAssertEqual(goldens.count, ids.count)
  }

  func testGoldenDetectsMissingTextWrongCellOrderAndImageCount() throws {
    let golden = try XCTUnwrap(DocumentGoldenAssertions.load().first { $0.id == "real-doc-02" })
    let blocks = [
      DocumentBlock(kind: .paragraph, text: "This is a Word document", readingOrder: 0),
      DocumentBlock(kind: .tableCell, text: "Cell 1,1", readingOrder: 1,
                    location: .init(row: 99, column: 1)),
      DocumentBlock(kind: .tableCell, text: "Cell 1,3", readingOrder: 2),
      DocumentBlock(kind: .tableCell, text: "Cell 1,2", readingOrder: 3)
    ]
    let result = DocumentParseResult(format: .doc, blocks: blocks, warnings: [])
    let failures = DocumentGoldenAssertions.violations(result, entry: golden)
    XCTAssertTrue(failures.contains { $0.hasPrefix("missingText") })
    XCTAssertTrue(failures.contains { $0.hasPrefix("readingOrder") })
    XCTAssertTrue(failures.contains { $0.hasPrefix("cell") })
    let imageGolden = try XCTUnwrap(DocumentGoldenAssertions.load().first {
      $0.id == "real-ppt-02"
    })
    XCTAssertTrue(DocumentGoldenAssertions.violations(result, entry: imageGolden)
      .contains("imageCount"))
  }
}
