import CoreHwp
import Foundation
import XCTest

@testable import Researchers

/// 같은 내용의 HWP·HWPX를 비교해 표 병합·그림 설명·논리적 앵커·복구 진단이 보존되는지 확인한다.
final class DocumentHWPComparisonTests: XCTestCase {
  func testNooriNativeTextCellsAndImageCountsAgree() async throws {
    let hwp = try source("real-hwp-01-noori", format: "hwp")
    let hwpx = try source("real-hwpx-02-noori", format: "hwpx")
    let first = try await DocumentParser.parse(.url(hwp),
      options: .init(extractImages: true, performOCR: true))
    let second = try await DocumentParser.parse(.url(hwpx),
      options: .init(extractImages: true, performOCR: true))
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
      let result = try await DocumentParser.parse(.url(source(name, format: format)),
        options: .init(extractImages: true, performOCR: true))
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
    XCTAssertFalse(diagnostics.isEmpty)
    XCTAssertFalse(diagnostics.contains {
      [.recoveredSection, .recoveredParagraph, .recoveredMemoParagraph].contains($0.kind)
    })
  }

  private func source(_ name: String, format: String) throws -> URL {
    try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: name, withExtension: format, subdirectory: "RealWorld/\(format)"))
  }
}
