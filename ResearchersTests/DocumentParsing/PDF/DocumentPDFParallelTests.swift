import Foundation
import Synchronization
import XCTest

@testable import Researchers

/// 직렬·병렬 결과, 이미지 예산, 진행률, 취소를 비교한다. 작업창 제한 때문에 OCR 대상이 빠져서는 안 된다.
final class DocumentPDFParallelTests: XCTestCase {
  func testParallelNativeScannedMixedResultsMatchSerialIncludingImageBudget() async throws {
    let data = try DocumentPDFParallelFixture.make()
    for images in [1, 128] {
      let serial = try await DocumentParser.parse(
        .data(data, fileName: "mixed.pdf"), options: .init(
        maximumEmbeddedImages: images, maximumConcurrentPDFPages: 1))
      let parallel = try await DocumentParser.parse(
        .data(data, fileName: "mixed.pdf"), options: .init(
        maximumEmbeddedImages: images, maximumConcurrentPDFPages: 4))
      XCTAssertEqual(parallel.fullText, serial.fullText)
      XCTAssertEqual(parallel.blocks, serial.blocks)
      XCTAssertEqual(parallel.images, serial.images)
      XCTAssertEqual(parallel.warnings, serial.warnings)
      XCTAssertEqual(parallel.blocks.map(\.readingOrder), Array(parallel.blocks.indices))
      let metrics = try XCTUnwrap(parallel.metrics)
      XCTAssertGreaterThan(metrics.peakInFlightPages, 1)
      XCTAssertLessThanOrEqual(metrics.peakInFlightPages, 4)
      XCTAssertEqual(Set(metrics.timings.compactMap(\.page)), Set(1...6))
      XCTAssertTrue(metrics.timings.allSatisfy { $0.seconds >= 0 && $0.startOffsetSeconds >= 0 })
      XCTAssertEqual(metrics.timings.filter { $0.stage == .pdfPageOCR }.count, 6)
    }
  }

  func testWorkingMemoryTargetSerializesWithoutDroppingOCR() async throws {
    let data = try DocumentPDFParallelFixture.make(pages: 3)
    var options = DocumentParserOptions(
      maximumConcurrentPDFPages: 4, pdfWorkingMemoryTargetBytes: 1)
    let result = try await DocumentParser.parse(
      .data(data, fileName: "memory.pdf"), options: options)
    XCTAssertEqual(result.metrics?.peakInFlightPages, 1)
    XCTAssertTrue(result.fullText.contains("Native Page 1"))
    XCTAssertTrue(result.fullText.contains("IMAGE"))
    XCTAssertEqual(Set(result.blocks.compactMap { $0.location.page }), Set(1...3))
    options.maximumConcurrentPDFPages = 0
    let mutated = try await DocumentParser.parse(
      .data(data, fileName: "memory.pdf"), options: options)
    XCTAssertEqual(mutated.fullText, result.fullText)
  }

  func testParallelCancellationStopsChildrenAndProgressIsMonotonic() async throws {
    let events = Mutex<[DocumentProgress]>([])
    let data = try DocumentPDFParallelFixture.make()
    let operation = Task {
      try await DocumentParser.parse(.data(data, fileName: "cancel.pdf")) { event in
        events.withLock { $0.append(event) }
        if event.phase == .recognizingText {
          withUnsafeCurrentTask { $0?.cancel() }
        }
      }
    }
    do {
      _ = try await operation.value
      XCTFail("Cancelled pipeline completed")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .cancelled) }
    let recorded = events.withLock { $0 }
    XCTAssertEqual(recorded.last?.phase, .cancelled)
    XCTAssertFalse(recorded.contains { $0.phase == .completed })
    let fractions = recorded.map(\.fractionCompleted)
    XCTAssertEqual(fractions, fractions.sorted())
  }

  func testBatchSharesPDFWindowAndKeepsInputOrder() async throws {
    let first = DocumentImageFixtures.multiPagePDF()
    let second = try DocumentPDFParallelFixture.make(pages: 3)
    let result = try await DocumentParser.parseBatch([
      .data(first, fileName: "first.pdf"), .data(second, fileName: "second.pdf")
    ], options: .init(maximumConcurrentDocuments: 2, maximumConcurrentPDFPages: 4))
    guard case .success(let one) = result[0], case .success(let two) = result[1] else {
      return XCTFail("Batch lost a PDF result")
    }
    XCTAssertTrue(one.fullText.contains("Page One Marker"))
    XCTAssertTrue(two.fullText.contains("Native Page 1"))
    XCTAssertLessThanOrEqual(try XCTUnwrap(one.metrics).peakInFlightPages, 4)
    XCTAssertLessThanOrEqual(try XCTUnwrap(two.metrics).peakInFlightPages, 4)
    let shared = try XCTUnwrap(two.metrics?.batchScheduling)
    XCTAssertLessThanOrEqual(shared.peakInFlightPages, 4)
    XCTAssertEqual(shared.activePages, 0)
    XCTAssertEqual(shared.waitingRequests, 0)
  }
}
