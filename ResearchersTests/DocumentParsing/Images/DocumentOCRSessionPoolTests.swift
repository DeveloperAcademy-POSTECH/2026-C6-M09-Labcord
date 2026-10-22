import ImageIO
import XCTest

@testable import Researchers

/// 새 Vision 요청과 재사용 세션의 결과·실패·병렬 접근·해제 수명을 비교한다. 이전 그림의 텍스트가 남으면 안 된다.
final class DocumentOCRSessionPoolTests: XCTestCase {
  func testReusedSessionMatchesFreshRecognitionAndDoesNotKeepPreviousText() throws {
    let pool = DocumentOCRSessionPool()
    let first = try XCTUnwrap(DocumentImageFixtures.textImage("SESSION FIRST 123"))
    let second = try XCTUnwrap(DocumentImageFixtures.textImage("한글 SECOND 456"))
    let blank = try XCTUnwrap(DocumentImageFixtures.textImage(""))
    for (image, orientation) in [(first, CGImagePropertyOrientation.up),
                                 (second, .up), (blank, .up), (first, .down)] {
      let fresh = try DocumentOCR.recognize(image: image, orientation: orientation)
      let reused = try DocumentOCR.$sessions.withValue(pool) {
        try DocumentOCR.recognize(image: image, orientation: orientation)
      }
      XCTAssertEqual(reused, fresh)
      if image === blank { XCTAssertTrue(reused.isEmpty) }
      XCTAssertEqual(pool.cachedSessionCount, 1)
    }
  }

  func testFailedSessionIsDiscarded() throws {
    let pool = DocumentOCRSessionPool()
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("SESSION FAILURE"))
    XCTAssertThrowsError(try pool.perform(image: image, orientation: .up) { _ in
      throw CancellationError()
    })
    XCTAssertEqual(pool.cachedSessionCount, 0)
    let result = try DocumentOCR.$sessions.withValue(pool) {
      try DocumentOCR.recognize(image: image, orientation: .up)
    }
    XCTAssertFalse(result.isEmpty)
    XCTAssertEqual(pool.cachedSessionCount, 1)
  }

  func testScopeReleasesPoolWhileResultsRemainUsable() throws {
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("SCOPED SESSION"))
    weak var reference: DocumentOCRSessionPool?
    let result: [DocumentBlock]
    do {
      let pool = DocumentOCRSessionPool()
      reference = pool
      result = try DocumentOCR.$sessions.withValue(pool) {
        try DocumentOCR.recognize(image: image, orientation: .up)
      }
    }
    XCTAssertNil(reference)
    XCTAssertFalse(result.isEmpty)
  }

  func testParallelCallsPreserveResultsAndBoundIdleSessions() async throws {
    let pool = DocumentOCRSessionPool()
    let raster = DocumentPDFRaster(
      image: try XCTUnwrap(DocumentImageFixtures.textImage("PARALLEL SESSION")))
    let expected = try DocumentOCR.recognize(image: raster.image, orientation: .up)
    XCTAssertFalse(expected.isEmpty)
    try await withThrowingTaskGroup(of: [DocumentBlock].self) { group in
      for _ in 0..<4 {
        group.addTask {
          try DocumentOCR.$sessions.withValue(pool) {
            try DocumentOCR.recognize(image: raster.image, orientation: .up)
          }
        }
      }
      for try await value in group { XCTAssertEqual(value, expected) }
    }
    XCTAssertGreaterThan(pool.cachedSessionCount, 0)
    XCTAssertLessThanOrEqual(pool.cachedSessionCount, 2)
  }
}
