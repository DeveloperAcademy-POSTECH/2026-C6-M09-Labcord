import Foundation
import UIKit
import XCTest

@testable import Researchers

/// 텍스트가 있는 PDF의 표 셀과 삽입 이미지에 실제 페이지 위치가 연결되는지 확인한다.
final class DocumentPDFStructureTests: XCTestCase {
  func testNativeTableCellsAndEmbeddedImagePositions() async throws {
    let label = try XCTUnwrap(DocumentImageFixtures.textImage("IMAGE OCR MARKER 123"))
    let data = DocumentImageFixtures.pdf { context in
      let graphics = context.cgContext
      for coordinateX in [40, 300, 560] {
        graphics.move(to: CGPoint(x: coordinateX, y: 80))
        graphics.addLine(to: CGPoint(x: coordinateX, y: 240))
      }
      for coordinateY in [80, 160, 240] {
        graphics.move(to: CGPoint(x: 40, y: coordinateY))
        graphics.addLine(to: CGPoint(x: 560, y: coordinateY))
      }
      graphics.strokePath()
      for (text, point) in [
        ("A1", CGPoint(x: 60, y: 100)), ("B1", CGPoint(x: 320, y: 100)),
        ("A2", CGPoint(x: 60, y: 180)), ("B2", CGPoint(x: 320, y: 180))
      ] {
        (text as NSString).draw(at: point, withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
      }
      UIImage(cgImage: label).draw(in: CGRect(x: 40, y: 450, width: 520, height: 104))
    }
    let result = try await DocumentParser.parse(.data(data, fileName: "structured.pdf"))
    let cells = result.blocks.filter { $0.kind == .tableCell }
    XCTAssertEqual(cells.map(\.text), ["A1", "B1", "A2", "B2"])
    XCTAssertEqual(cells.map { $0.location.row }, [1, 1, 2, 2])
    XCTAssertEqual(cells.map { $0.location.column }, [1, 2, 1, 2])
    XCTAssertEqual(result.fullText.components(separatedBy: "A1").count - 1, 1)
    let attachment = try XCTUnwrap(result.images.first)
    let bounds = try XCTUnwrap(attachment.location.bounds)
    XCTAssertEqual(bounds.minX, 40.0 / 612.0, accuracy: 0.01)
    XCTAssertEqual(bounds.minY, 450.0 / 792.0, accuracy: 0.01)
    XCTAssertEqual(bounds.width, 520.0 / 612.0, accuracy: 0.01)
    XCTAssertEqual(attachment.location.page, 1)
    XCTAssertNotNil(UIImage(data: attachment.pngData))
    XCTAssertTrue(
      result.blocks.contains {
        $0.kind == .imageOCR && $0.text.contains("IMAGE OCR MARKER")
          && $0.location.part == attachment.location.part
      })
  }
}
