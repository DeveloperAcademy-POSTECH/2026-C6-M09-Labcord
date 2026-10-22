import Foundation
import UIKit
import XCTest

@testable import Researchers

/// 전체 페이지와 정확히 같은 그림만 OCR을 재사용하는지 확인한다. 부분 그림과 예산 제한은 별도로 처리해야 한다.
final class DocumentPDFRecognitionReuseTests: XCTestCase {
  func testFullPageReuseAndLimitedImageFallbackKeepText() async throws {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 612, height: 792))
    let image = renderer.image { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
      ("한글 FULL PAGE 123" as NSString).draw(at: CGPoint(x: 40, y: 80),
        withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
    }
    let data = DocumentImageFixtures.pdf { context in
      image.draw(in: context.pdfContextBounds)
    }
    let reused = try await DocumentParser.parse(.data(data, fileName: "full-page.pdf"))
    let fallback = try await DocumentParser.parse(
      .data(data, fileName: "full-page.pdf"), options: .init(
      maximumPDFImageBytes: 1))
    XCTAssertEqual(reused.images.count, 1)
    XCTAssertTrue(fallback.images.isEmpty)
    XCTAssertEqual(reused.fullText, fallback.fullText)
    XCTAssertTrue(reused.fullText.contains("FULL PAGE"))
    XCTAssertEqual(reused.metrics?.timings.filter { $0.stage == .pdfPageOCRReuse }.count, 1)
    XCTAssertEqual(reused.metrics?.timings.filter { $0.stage == .pdfPageOCR }.count, 0)
    XCTAssertEqual(fallback.metrics?.timings.filter { $0.stage == .pdfPageOCR }.count, 1)
  }

  func testPartialImagesContinueWholePageRecognition() async throws {
    let data = try DocumentPDFParallelFixture.make(pages: 3)
    let result = try await DocumentParser.parse(.data(data, fileName: "partial.pdf"))
    XCTAssertEqual(result.metrics?.timings.filter { $0.stage == .pdfPageOCRReuse }.count, 0)
    XCTAssertEqual(result.metrics?.timings.filter { $0.stage == .pdfPageOCR }.count, 3)
    XCTAssertTrue(result.fullText.contains("IMAGE"))
  }
}
