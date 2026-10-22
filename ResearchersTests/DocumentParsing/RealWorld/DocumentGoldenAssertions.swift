import Foundation
import XCTest

@testable import Researchers

/// 검증된 원본 해시와 부분 정답만 비교한다. 파서 출력 자체를 다시 정답으로 만드는 도우미가 아니다.
nonisolated enum DocumentGoldenAssertions {
  struct Entry: Decodable {
    let id: String
    let sha256: String
    let evidence: String
    let textAnchors: [String]
    let orderedText: [String]
    let sourceTextRuns: [String]
    let cells: [Cell]
    let exactImages: Int?
  }

  struct Cell: Decodable {
    let row: Int
    let column: Int
    let rowSpan: Int?
    let columnSpan: Int?
    let text: String
  }

  static func load() throws -> [Entry] {
    let url = try XCTUnwrap(Bundle(for: DocumentRealWorldCorpusTests.self).url(
      forResource: "GoldenAssertions", withExtension: "json", subdirectory: "RealWorld"))
    return try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
  }

  static func verify(_ result: DocumentParseResult, id: String, sha256: String) throws {
    let entry = try XCTUnwrap(load().first { $0.id == id })
    XCTAssertEqual(entry.sha256, sha256, "\(id): golden source hash")
    XCTAssertFalse(entry.evidence.isEmpty, id)
    XCTAssertEqual(violations(result, entry: entry), [], id)
  }

  // 정답 생성은 원본을 사용하며, 이 함수는 실제 결과를 정답과 비교만 한다.
  static func violations(_ result: DocumentParseResult, entry: Entry) -> [String] {
    var failures: [String] = []
    let text = compact(result.fullText)
    for (index, anchor) in (entry.textAnchors + entry.sourceTextRuns).enumerated()
    where !text.contains(compact(anchor)) {
      failures.append("missingText[\(index)]")
    }
    var cursor = text.startIndex
    for (index, anchor) in entry.orderedText.enumerated() {
      if let range = text.range(of: compact(anchor), range: cursor..<text.endIndex) {
        cursor = range.upperBound
      } else {
        failures.append("readingOrder[\(index)]")
      }
    }
    var cells = result.blocks.filter { $0.kind == .tableCell }
    for (index, expected) in entry.cells.enumerated() {
      if let match = cells.firstIndex(where: {
        $0.location.row == expected.row && $0.location.column == expected.column
          && compact($0.text) == compact(expected.text)
          && (expected.rowSpan == nil || expected.rowSpan == $0.location.rowSpan)
          && (expected.columnSpan == nil || expected.columnSpan == $0.location.columnSpan)
      }) {
        cells.remove(at: match)
      } else {
        failures.append("cell[\(index)]")
      }
    }
    if let count = entry.exactImages, result.images.count != count {
      failures.append("imageCount")
    }
    return failures
  }

  private static func compact(_ text: String) -> String {
    String(text.filter { !$0.isWhitespace })
  }
}
