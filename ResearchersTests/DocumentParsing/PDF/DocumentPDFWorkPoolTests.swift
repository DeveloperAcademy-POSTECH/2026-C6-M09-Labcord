import Foundation
import XCTest

@testable import Researchers

/// 공용 페이지 슬롯·바이트 예약의 대여·취소·반환을 확인한다. 큰 페이지가 영원히 대기하거나 예약이 남으면 안 된다.
final class DocumentPDFWorkPoolTests: XCTestCase {
  func testCapacityReturnsToRemainingDocument() async throws {
    let pool = DocumentPDFWorkPool(options: .init(
      maximumConcurrentPDFPages: 2, pdfWorkingMemoryTargetBytes: 20))
    let one = try await pool.acquire(estimatedBytes: 10)
    let two = try await pool.acquire(estimatedBytes: 10)
    let waiting = Task { try await pool.acquire(estimatedBytes: 10) }
    try await waitForQueue(pool)
    await pool.release(one)
    let borrowed = try await waiting.value
    var metrics = await pool.snapshot()
    XCTAssertEqual(metrics.activePages, 2)
    XCTAssertEqual(metrics.peakInFlightPages, 2)
    await pool.release(two)
    await pool.release(borrowed)
    metrics = await pool.snapshot()
    XCTAssertEqual(metrics.activePages, 0)
    XCTAssertEqual(metrics.waitingRequests, 0)
  }

  func testCancellationRemovesWaiterWithoutLeakingPermit() async throws {
    let pool = DocumentPDFWorkPool(options: .init(maximumConcurrentPDFPages: 1))
    let first = try await pool.acquire(estimatedBytes: 10)
    let waiting = Task { try await pool.acquire(estimatedBytes: 10) }
    try await waitForQueue(pool)
    waiting.cancel()
    do {
      _ = try await waiting.value
      XCTFail("Cancelled waiter received a permit")
    } catch { XCTAssertTrue(error is CancellationError) }
    await pool.release(first)
    let next = try await pool.acquire(estimatedBytes: 10)
    await pool.release(next)
    let metrics = await pool.snapshot()
    XCTAssertEqual(metrics.activePages, 0)
    XCTAssertEqual(metrics.waitingRequests, 0)
  }

  func testMemoryTargetAndOversizedPageProgressWithoutDeadlock() async throws {
    let pool = DocumentPDFWorkPool(options: .init(
      maximumConcurrentPDFPages: 4, pdfWorkingMemoryTargetBytes: 20))
    let first = try await pool.acquire(estimatedBytes: 15)
    await pool.resize(first, actualBytes: 19)
    let waiting = Task { try await pool.acquire(estimatedBytes: 50) }
    try await waitForQueue(pool)
    let occupied = await pool.snapshot()
    XCTAssertEqual(occupied.activePages, 1)
    await pool.release(first)
    let oversized = try await waiting.value
    let metrics = await pool.snapshot()
    XCTAssertEqual(metrics.activePages, 1)
    XCTAssertEqual(metrics.peakEstimatedWorkingBytes, 50)
    await pool.release(oversized)
  }

  func testDynamicBatchBorrowsWindowAndByteLimitPreservesPageOCR() async throws {
    let data = try DocumentPDFParallelFixture.make(pages: 9)
    let results = try await DocumentParser.parseBatch([
      .data(DocumentImageFixtures.multiPagePDF(), fileName: "short.pdf"),
      .data(data, fileName: "long.pdf")
    ], options: .init(maximumConcurrentDocuments: 2, maximumConcurrentPDFPages: 4))
    guard case .success(let long) = results[1] else { return XCTFail("Long PDF failed") }
    XCTAssertGreaterThan(try XCTUnwrap(long.metrics).peakInFlightPages, 2)
    XCTAssertLessThanOrEqual(try XCTUnwrap(long.metrics?.batchScheduling).peakInFlightPages, 4)
    let limited = try await DocumentParser.parse(
      .data(data, fileName: "limited.pdf"), options: .init(
      maximumPDFImageBytes: 1))
    XCTAssertTrue(limited.images.isEmpty)
    XCTAssertTrue(limited.fullText.contains("IMAGE"))
    XCTAssertTrue(limited.warnings.contains { $0.code == .resourceLimitReached })
    XCTAssertEqual(limited.metrics?.timings.filter { $0.stage == .pdfPageOCR }.count, 9)
  }

  func testCancelledPipelineReturnsEverySharedPermit() async throws {
    let pool = DocumentPDFWorkPool(options: .init(maximumConcurrentPDFPages: 1))
    let data = try DocumentPDFParallelFixture.make(pages: 9)
    let operation = Task {
      try await DocumentPDFScheduling.$pool.withValue(pool) {
        try await DocumentParser.parse(.data(data, fileName: "cancel.pdf"), options: .init(
          maximumConcurrentPDFPages: 4)) { event in
          if event.phase == .recognizingText { withUnsafeCurrentTask { $0?.cancel() } }
        }
      }
    }
    do {
      _ = try await operation.value
      XCTFail("Cancelled pipeline completed")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .cancelled) }
    let metrics = await pool.snapshot()
    XCTAssertEqual(metrics.activePages, 0)
    XCTAssertEqual(metrics.waitingRequests, 0)
  }

  private func waitForQueue(_ pool: DocumentPDFWorkPool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while await pool.snapshot().waitingRequests == 0, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(1))
    }
    let metrics = await pool.snapshot()
    XCTAssertGreaterThan(metrics.waitingRequests, 0)
  }
}
