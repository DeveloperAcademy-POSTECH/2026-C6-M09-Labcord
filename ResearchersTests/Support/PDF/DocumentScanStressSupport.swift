import CryptoKit
import Foundation
import PDFKit
import UIKit
import XCTest

@testable import Researchers

/// 대용량 원본의 로딩·결과 일관성·임시 폴더 정리를 확인한다.
nonisolated enum DocumentScanStressSupport {
  static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func url(_ name: String) throws -> URL {
    try XCTUnwrap(Bundle(for: DocumentLargeScanTests.self).url(
      forResource: name, withExtension: "pdf", subdirectory: "RealWorld/LargeScans"))
  }

  static func rasterOnly() throws -> Data {
    let original = try XCTUnwrap(PDFDocument(url: url("usgs-wsp158")))
    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
    let pages = try (0..<original.pageCount).map { try XCTUnwrap(original.page(at: $0)) }
    return renderer.pdfData { context in
      for page in pages {
        let image = page.thumbnail(of: CGSize(width: 1224, height: 1584), for: .mediaBox)
        context.beginPage()
        image.draw(in: CGRect(x: 0, y: 0, width: 612, height: 792))
      }
    }
  }

  static func check(_ result: DocumentParseResult, pages: Int) throws {
    XCTAssertEqual(result.blocks.map(\.readingOrder), Array(result.blocks.indices))
    let pageNumbers = result.blocks.compactMap { $0.location.page }
    XCTAssertEqual(pageNumbers, pageNumbers.sorted())
    XCTAssertTrue(pageNumbers.allSatisfy { (1...pages).contains($0) })
    XCTAssertGreaterThan(result.fullText.count, pages * 100)
    XCTAssertEqual(result.fullText, result.blocks.filter {
      [.paragraph, .heading, .tableCell, .imageOCR].contains($0.kind)
    }.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n"))
    XCTAssertFalse(result.warnings.contains {
      [.extractionFailed, .imageOCRFailed, .malformedContent].contains($0.code)
    })
  }

  static func temporaryDirectories() throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(
      atPath: FileManager.default.temporaryDirectory.path).filter {
        $0.hasPrefix("DocumentParsing-")
      })
  }
}
