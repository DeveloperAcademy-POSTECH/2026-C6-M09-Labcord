import Foundation
import PDFKit
import XCTest

@testable import Researchers

/// 한국어 원본 해시·페이지 수와 선택한 페이지의 기준 문구를 확인한다. 전 페이지 정답 데이터를 제공하지는 않는다.
nonisolated enum DocumentKoreanScanAssertions {
  static func verifyOriginal(_ url: URL) throws {
    let data = try Data(contentsOf: url)
    XCTAssertEqual(DocumentScanStressSupport.digest(data),
                   "ed5e2e45c85d80df416d14380004afcab6dff59bc9135a3d111948377e2d0d7d")
    let document = try XCTUnwrap(PDFDocument(data: data))
    XCTAssertEqual(document.pageCount, 125)
    XCTAssertTrue((0..<125).allSatisfy { document.page(at: $0)?.string?.isEmpty != false })
  }

  static func verifyResult(_ result: DocumentParseResult) {
    XCTAssertEqual(result.images.count, 125)
    XCTAssertTrue(result.blocks.allSatisfy { $0.kind == .image || $0.kind == .imageOCR })
    XCTAssertFalse(result.warnings.contains { $0.code == .resourceLimitReached })
    // 원본 스캔 4·11·60·125쪽을 직접 읽어 선택했다. 전체 OCR 정확도의 정답지는 아니다.
    for (page, phrases) in [
      (4, ["국립국어연구원", "1992년", "국민"]),
      (11, ["언어규범", "언어예절", "이름짓기"]),
      (60, ["표준어", "결론부터", "표준어규정"]),
      (125, ["자료집", "1992년", "국립국어연구원"])
    ] {
      let text = result.blocks.filter { $0.location.page == page }.map(\.text).joined()
        .filter { !$0.isWhitespace }
      for phrase in phrases {
        XCTAssertTrue(text.contains(phrase), "page \(page): missing anchor")
      }
    }
  }
}
