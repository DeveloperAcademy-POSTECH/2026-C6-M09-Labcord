import CoreHwp
import Foundation
import ImageIO
import UIKit
import XCTest

@testable import Researchers

/// 실제 바이너리 Office·HWP 샘플과 다중 프레임 TIFF의 본문·표·그림·부분 실패를 확인한다.
final class DocumentRemainingFormatTests: XCTestCase {
  func testBinaryHWPBodyTableAndImage() async throws {
    for name in ["BinarySample", "BinaryCompressed"] {
      try await verifyHWP(name)
    }
  }

  private func verifyHWP(_ name: String) async throws {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(
        forResource: name, withExtension: "hwp"))
    _ = try HwpFile(fromData: Data(contentsOf: url))
    let result = try await DocumentParser.parse(.data(Data(contentsOf: url), fileName: nil))
    XCTAssertEqual(result.format, .hwp)
    XCTAssertFalse(result.images.isEmpty)
    XCTAssertTrue(result.fullText.contains("HWP body marker"))
    XCTAssertTrue(
      result.blocks.contains {
        $0.kind == .tableCell && $0.text == "HWP cell marker"
      })
    XCTAssertTrue(
      result.blocks.contains {
        $0.kind == .imageOCR && $0.text.contains("IMAGE OCR MARKER")
      })
  }

  func testLegacyDOCBodyTableAndImage() async throws { try await verifyLegacy(.doc) }
  func testLegacyXLSBodyTableAndImage() async throws { try await verifyLegacy(.xls) }
  func testLegacyPPTBodyTableAndImage() async throws { try await verifyLegacy(.ppt) }

  private func verifyLegacy(_ format: DocumentFormat) async throws {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(
        forResource: "LegacySample", withExtension: format.rawValue))
    let data = try Data(contentsOf: url)
    XCTAssertTrue(data.starts(with: [0xD0, 0xCF, 0x11, 0xE0]))
    let result = try await DocumentParser.parse(.data(data, fileName: nil))
    XCTAssertEqual(result.format, format)
    XCTAssertFalse(result.images.isEmpty)
    XCTAssertFalse(result.fullText.contains("Click to edit"))
    XCTAssertTrue(result.fullText.contains("Legacy body marker"))
    XCTAssertTrue(
      result.blocks.contains {
        $0.kind == .tableCell && $0.text.contains("Legacy cell marker")
      })
    XCTAssertTrue(
      result.blocks.contains {
        $0.kind == .imageOCR && $0.text.contains("IMAGE OCR MARKER")
      })
  }

  func testTIFFMultipleFramesKeepPageOrderAndOrientation() async throws {
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("PAGE FIRST 123"))
    let second = try XCTUnwrap(DocumentImageFixtures.textImage("PAGE SECOND 456"))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let rotated = UIGraphicsImageRenderer(
      size: CGSize(width: second.height, height: second.width), format: format
    ).image { context in
      context.cgContext.translateBy(x: CGFloat(second.height), y: 0)
      context.cgContext.rotate(by: .pi / 2)
      UIImage(cgImage: second).draw(
        in: CGRect(x: 0, y: 0, width: second.width, height: second.height))
    }
    let rotatedImage = try XCTUnwrap(rotated.cgImage)
    let tiff = try DocumentImageFixtures.tiff([(image, .up), (rotatedImage, .left)])
    let result = try await DocumentParser.parse(.data(tiff, fileName: "pages.tiff"))
    XCTAssertEqual(result.format, .tiff)
    XCTAssertTrue(result.blocks.contains { $0.location.page == 1 && $0.text.contains("FIRST") })
    XCTAssertTrue(result.blocks.contains { $0.location.page == 2 && $0.text.contains("SECOND") })
    XCTAssertEqual(result.blocks.map(\.readingOrder), Array(result.blocks.indices))
  }

  func testTIFFOverLimitFramePreservesOtherFrames() async throws {
    let small = try XCTUnwrap(DocumentImageFixtures.textImage("KEPT PAGE 123"))
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2_000, height: 1_000))
    let large = renderer.image { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 2_000, height: 1_000))
    }
    let largeImage = try XCTUnwrap(large.cgImage)
    let tiff = try DocumentImageFixtures.tiff([(small, .up), (largeImage, .up), (small, .up)])
    let result = try await DocumentParser.parse(
      .data(tiff, fileName: "partial.tiff"), options: .init(maximumImagePixels: 300_000))
    XCTAssertTrue(result.blocks.contains { $0.location.page == 1 })
    XCTAssertTrue(result.blocks.contains { $0.location.page == 3 })
    XCTAssertTrue(
      result.warnings.contains {
        $0.location?.page == 2 && $0.code == .resourceLimitReached
      })
  }

}
