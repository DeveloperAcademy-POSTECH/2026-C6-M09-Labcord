import Foundation
import ImageIO
import XCTest

@testable import Researchers

/// 프레임·페이지·연산 한도에 걸려도 앞서 읽은 결과와 위치 경고가 유지되는지 확인한다.
final class DocumentFrameResourceTests: XCTestCase {
  func testTIFFPageLimitKeepsFirstFrameAndWarningLocation() async throws {
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("KEPT FRAME 123"))
    let data = try DocumentImageFixtures.tiff([(image, .up), (image, .up)])
    let result = try await DocumentParser.parse(
      .data(data, fileName: "limit.tiff"), options: .init(maximumDocumentPages: 1))
    XCTAssertFalse(result.blocks.isEmpty)
    XCTAssertTrue(result.blocks.allSatisfy { $0.location.page == 1 })
    XCTAssertTrue(result.warnings.contains {
      $0.code == .resourceLimitReached && $0.location?.page == 2
    })
  }

  func testTIFFCancellationBetweenFramesPropagates() async throws {
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("CANCEL FRAME 123"))
    let data = try DocumentImageFixtures.tiff([(image, .up), (image, .up)])
    let operation = Task {
      try await DocumentParser.parse(.data(data, fileName: "cancel.tiff")) { event in
        if event.phase == .recognizingText {
          withUnsafeCurrentTask { $0?.cancel() }
        }
      }
    }
    do {
      _ = try await operation.value
      XCTFail("TIFF parsing ignored cancellation between frames.")
    } catch {
      XCTAssertEqual(error as? DocumentParsingError, .cancelled)
    }
  }

  func testPDFPageAndOperatorLimitsPreservePartialResults() async throws {
    let result = try await DocumentParser.parse(
      .data(DocumentImageFixtures.multiPagePDF(), fileName: "limit.pdf"),
      options: .init(maximumDocumentPages: 1))
    XCTAssertTrue(result.fullText.contains("Page One"))
    XCTAssertFalse(result.fullText.contains("Page Two"))
    XCTAssertTrue(result.warnings.contains {
      $0.code == .resourceLimitReached && $0.location?.page == 2
    })
    let drawing = try await DocumentParser.parse(
      .data(DocumentPDFRawFixture.nestedImages(), fileName: "operators.pdf"),
      options: .init(maximumPDFOperators: 1))
    XCTAssertTrue(drawing.images.isEmpty)
    XCTAssertTrue(drawing.warnings.contains { $0.code == .resourceLimitReached })
  }

  func testMixedBinaryTIFFAndPDFBatchKeepsInputOrder() async throws {
    let binary = try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: "LegacySample", withExtension: "doc"))
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("BATCH FRAME 123"))
    let tiff = try DocumentImageFixtures.tiff([(image, .up)])
    let results = try await DocumentParser.parseBatch([
      .url(binary), .data(tiff, fileName: nil),
      .data(DocumentPDFRawFixture.nestedImages(), fileName: nil)
    ])
    let formats = results.compactMap { result -> DocumentFormat? in
      guard case .success(let document) = result else { return nil }
      return document.format
    }
    XCTAssertEqual(formats, [.doc, .tiff, .pdf])
  }

  func testTIFFRecognizesKoreanAndEnglishOnDevice() async throws {
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("한글 ENGLISH"))
    let data = try DocumentImageFixtures.tiff([(image, .up)])
    let result = try await DocumentParser.parse(.data(data, fileName: "languages.tiff"))
    XCTAssertTrue(result.fullText.contains("한글"))
    XCTAssertTrue(result.fullText.uppercased().contains("ENGLISH"))
  }
}
