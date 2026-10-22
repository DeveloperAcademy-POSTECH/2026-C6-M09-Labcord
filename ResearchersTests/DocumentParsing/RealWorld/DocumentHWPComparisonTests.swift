import CoreHwp
import Foundation
import XCTest

@testable import Researchers

/// 같은 내용의 HWP·HWPX를 비교해 표 병합·그림 설명·논리적 앵커·복구 진단이 보존되는지 확인한다.
final class DocumentHWPComparisonTests: XCTestCase {
  func testNooriNativeTextCellsAndImageCountsAgree() async throws {
    let hwp = try source("real-hwp-01-noori", format: "hwp")
    let hwpx = try source("real-hwpx-02-noori", format: "hwpx")
    let first = try await DocumentParser.parse(.url(hwp))
    let second = try await DocumentParser.parse(.url(hwpx))
    let native: (DocumentParseResult) -> [DocumentBlock] = {
      $0.blocks.filter { $0.kind != .imageOCR && $0.kind != .image }
    }
    XCTAssertEqual(native(first), native(second))
    XCTAssertEqual(first.images.count, 4)
    XCTAssertEqual(second.images.count, 4)
    XCTAssertEqual(first.blocks.filter { $0.kind == .tableCell }.count, 36)
    XCTAssertEqual(second.blocks.filter { $0.kind == .table }.count, 5)
    // BinData 순서가 달라 OCR은 전체 순서 대신 동일한 문구의 중복 개수까지 비교한다.
    let ocr: (DocumentParseResult) -> [String] = {
      $0.blocks.filter { $0.kind == .imageOCR }.map(\.text).sorted()
    }
    XCTAssertEqual(ocr(first), ocr(second))
    XCTAssertTrue(second.warnings.contains { $0.code == .uncertainReadingOrder })
  }

  func testNooriMergedCellsDescriptionsAndLogicalImageAnchors() async throws {
    for (name, format) in [("real-hwp-01-noori", "hwp"), ("real-hwpx-02-noori", "hwpx")] {
      let result = try await DocumentParser.parse(.url(source(name, format: format)))
      XCTAssertTrue(result.blocks.contains {
        $0.kind == .tableCell && $0.location.columnSpan == 3 && $0.location.rowSpan == 1
      }, format)
      XCTAssertEqual(result.images.compactMap(\.sourceDescription).count, 3, format)
      XCTAssertTrue(result.images.contains {
        $0.sourceDescription?.contains("보도_생태계.jpg") == true
      }, format)
      XCTAssertTrue(result.images.allSatisfy {
        $0.location.part?.hasPrefix("section[") == true && $0.location.paragraph != nil
      }, format)
      XCTAssertEqual(result.images.filter { $0.location.row != nil }.count, 3, format)
      XCTAssertEqual(result.blocks.filter { $0.kind == .image }.count, 4, format)
      XCTAssertFalse(result.fullText.contains("원본 그림의 이름"), format)
    }
  }

  func testRecoveredMemoProducesExtractionFailure() {
    var context = DocumentHWPParseContext(options: .init())
    context.appendDiagnostics([
      HwpParseDiagnostic(kind: .recoveredMemoParagraph, path: "section[0].memo[0]")
    ])
    XCTAssertEqual(context.warnings.first?.code, .extractionFailed)
    XCTAssertEqual(context.warnings.first?.location?.part, "section[0].memo[0]")
  }

  func testNooriBackendDiagnosticsAreClassifiedWithoutDroppingWarnings() throws {
    let url = try source("real-hwpx-02-noori", format: "hwpx")
    let file = try HwpFile(fromData: Data(contentsOf: url), options: HwpLoadOptions(
      preserveRawPayload: false, recoverPartialContent: true))
    let diagnostics = file.parseDiagnostics()
    let groups = Dictionary(grouping: diagnostics) { diagnostic in
      "\(diagnostic.kind.rawValue):\(diagnostic.detail ?? "unspecified")"
    }.mapValues(\.count)
    let report: [String: Any] = [
      "fixture": "hwpx-02-noori", "total": diagnostics.count, "groups": groups,
      "unknownElementNames": unknownNames(in: [file.docInfo, file.sectionArray] as [Any]),
      "docInfo": diagnostics.filter { $0.path.hasPrefix("docInfo") }.count,
      "section": diagnostics.filter { $0.path.hasPrefix("section") }.count
    ]
    let attachment = XCTAttachment(
      data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
      uniformTypeIdentifier: "public.json")
    attachment.name = "noori-backend-diagnostics"
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertFalse(diagnostics.isEmpty)
    XCTAssertFalse(diagnostics.contains {
      [.recoveredSection, .recoveredParagraph, .recoveredMemoParagraph].contains($0.kind)
    })
  }

  // HWPX 합성 unknown record는 tag 0과 XML 요소명만 보존한다.
  // 공개 시험 원본에만 reflection을 사용하며 payload 본문은 첨부하지 않는다.
  private func unknownNames(in value: Any, depth: Int = 0) -> [String: Int] {
    guard depth < 128, !(value is Data), !(value is String) else { return [:] }
    var counts: [String: Int] = [:]
    if let record = value as? HwpUnknownRecord {
      if record.tagId == 0, let name = String(data: record.payload, encoding: .utf8) {
        counts[name, default: 0] += 1
      }
      for child in record.children {
        counts.merge(unknownNames(in: child, depth: depth + 1), uniquingKeysWith: +)
      }
      return counts
    }
    for child in Mirror(reflecting: value).children {
      counts.merge(unknownNames(in: child.value, depth: depth + 1), uniquingKeysWith: +)
    }
    return counts
  }

  private func source(_ name: String, format: String) throws -> URL {
    try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: name, withExtension: format, subdirectory: "RealWorld/\(format)"))
  }
}
