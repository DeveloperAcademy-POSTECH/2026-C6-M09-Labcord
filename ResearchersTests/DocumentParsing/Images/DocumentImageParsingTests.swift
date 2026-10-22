import Foundation
import UIKit
import XCTest

@testable import Researchers

/// 직접 이미지 OCR과 일반·스캔·혼합 PDF를 확인한다. 같은 본문이 OCR 결과로 중복 추가되지 않아야 한다.
final class DocumentImageParsingTests: XCTestCase {
  func testImageOCRReturnsNormalizedLocationAndConfidence() async throws {
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("LABCORD 123"))
    let result = try await DocumentParser.parse(.image(image, orientation: .up))
    let textBlock = try XCTUnwrap(result.blocks.first)
    XCTAssertEqual(textBlock.kind, .imageOCR)
    XCTAssertGreaterThanOrEqual(textBlock.ocrConfidence ?? 0, 0)
    XCTAssertGreaterThanOrEqual(textBlock.location.bounds?.minX ?? -1, 0)
    XCTAssertTrue(result.fullText.contains("LABCORD"))
  }

  func testPDFNativeScannedAndMixedPages() async throws {
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("LABCORD 123"))
    let imagePDF = DocumentImageFixtures.pdf { _ in
      UIImage(cgImage: image).draw(in: CGRect(x: 40, y: 400, width: 520, height: 100))
    }
    let scan = try await DocumentParser.parse(.data(imagePDF, fileName: "scan.pdf"))
    XCTAssertTrue(scan.fullText.contains("LABCORD"), scan.fullText)

    let mixedPDF = DocumentImageFixtures.pdf { _ in
      ("Native Marker 123" as NSString).draw(
        at: CGPoint(x: 40, y: 700),
        withAttributes: [.font: UIFont.systemFont(ofSize: 28)]
      )
      UIImage(cgImage: image).draw(in: CGRect(x: 40, y: 400, width: 520, height: 100))
    }
    let mixed = try await DocumentParser.parse(.data(mixedPDF, fileName: "mixed.pdf"))
    XCTAssertTrue(mixed.fullText.contains("Native Marker"))
    XCTAssertTrue(mixed.fullText.contains("LABCORD"), mixed.fullText)
    XCTAssertEqual(mixed.blocks.filter { $0.text.contains("Native Marker") }.count, 1)

    let limited = try await DocumentParser.parse(
      .data(mixedPDF, fileName: "limited.pdf"),
      options: .init(maximumImagePixels: 1)
    )
    XCTAssertTrue(limited.fullText.contains("Native Marker"))
    XCTAssertTrue(
      limited.warnings.contains {
        $0.code == .resourceLimitReached && $0.location?.page == 1
      })

    let pagedResult = try await DocumentParser.parse(
      .data(DocumentImageFixtures.multiPagePDF(), fileName: "ordered-pages.pdf")
    )
    let pageOneIndex = try XCTUnwrap(
      pagedResult.blocks.firstIndex { $0.text.contains("Page One") })
    let pageTwoIndex = try XCTUnwrap(
      pagedResult.blocks.firstIndex { $0.text.contains("Page Two") })
    XCTAssertLessThan(pageOneIndex, pageTwoIndex)
    XCTAssertEqual(pagedResult.blocks[pageOneIndex].location.page, 1)
    XCTAssertEqual(pagedResult.blocks[pageTwoIndex].location.page, 2)
  }
}
