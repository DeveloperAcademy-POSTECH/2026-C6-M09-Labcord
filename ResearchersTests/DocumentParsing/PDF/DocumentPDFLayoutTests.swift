import Foundation
import UIKit
import XCTest

@testable import Researchers

/// 회전·중첩 Form·반복 그림·병합 셀 등에서 표시 위치와 읽기 순서 경고를 확인한다.
final class DocumentPDFLayoutTests: XCTestCase {
  func testNestedFormMatrixAndPageRotationLocateImage() async throws {
    for (rotation, expected) in [
      (0, CGRect(x: 0.2, y: 0.45, width: 0.25, height: 0.25)),
      (90, CGRect(x: 0.3, y: 0.2, width: 0.25, height: 0.25))
    ] {
      let result = try await DocumentParser.parse(
        .data(
          DocumentPDFRawFixture.nestedImages(rotation: rotation), fileName: "form.pdf"))
      let actual = try XCTUnwrap(result.images.first?.location.bounds)
      XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.005)
      XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.005)
      XCTAssertEqual(actual.width, expected.width, accuracy: 0.005)
      XCTAssertEqual(actual.height, expected.height, accuracy: 0.005)
    }
  }

  func testRepeatedImagePlacementsRespectAttachmentLimit() async throws {
    let data = DocumentPDFRawFixture.nestedImages(repeated: true)
    let complete = try await DocumentParser.parse(.data(data, fileName: "repeat.pdf"))
    XCTAssertEqual(complete.images.count, 2)
    XCTAssertNotEqual(complete.images[0].location.bounds, complete.images[1].location.bounds)
    let limited = try await DocumentParser.parse(
      .data(data, fileName: "limit.pdf"), options: .init(maximumEmbeddedImages: 1))
    XCTAssertEqual(limited.images.count, 1)
    XCTAssertTrue(limited.warnings.contains { $0.code == .resourceLimitReached })
  }

  func testBorderlessNativeTableReturnsLocatedCellsAndWarning() async throws {
    let data = DocumentImageFixtures.pdf { _ in
      for row in 0..<4 {
        for column in 0..<2 {
          ("Value \(row)-\(column)" as NSString).draw(
            at: CGPoint(x: 40 + column * 280, y: 80 + row * 45),
            withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
        }
      }
    }
    let result = try await DocumentParser.parse(.data(data, fileName: "borderless.pdf"))
    let cells = result.blocks.filter { $0.kind == .tableCell }
    XCTAssertEqual(cells.count, 8)
    XCTAssertEqual(cells.first?.text, "Value 0-0")
    XCTAssertEqual(cells.last?.location.row, 4)
    XCTAssertEqual(cells.last?.location.column, 2)
    XCTAssertTrue(
      result.warnings.contains {
        $0.code == .uncertainReadingOrder && $0.location?.bounds != nil
      })
  }

  func testMergedNativeCellHasColumnSpan() async throws {
    let data = DocumentImageFixtures.pdf { context in
      let graphics = context.cgContext
      for coordinate in [80, 160, 240] {
        graphics.move(to: CGPoint(x: 40, y: coordinate))
        graphics.addLine(to: CGPoint(x: 560, y: coordinate))
      }
      for coordinate in [40, 560] {
        graphics.move(to: CGPoint(x: coordinate, y: 80))
        graphics.addLine(to: CGPoint(x: coordinate, y: 240))
      }
      graphics.move(to: CGPoint(x: 300, y: 160))
      graphics.addLine(to: CGPoint(x: 300, y: 240))
      graphics.strokePath()
      for (text, point) in [
        ("Merged", CGPoint(x: 60, y: 100)),
        ("Left", CGPoint(x: 60, y: 180)), ("Right", CGPoint(x: 320, y: 180))
      ] {
        (text as NSString).draw(at: point, withAttributes: [.font: UIFont.systemFont(ofSize: 22)])
      }
    }
    let result = try await DocumentParser.parse(.data(data, fileName: "merged.pdf"))
    let merged = try XCTUnwrap(
      result.blocks.first { $0.kind == .tableCell && $0.text == "Merged" })
    XCTAssertEqual(merged.location.columnSpan, 2)
    XCTAssertEqual(result.blocks.filter { $0.kind == .tableCell }.count, 3)
  }
}
