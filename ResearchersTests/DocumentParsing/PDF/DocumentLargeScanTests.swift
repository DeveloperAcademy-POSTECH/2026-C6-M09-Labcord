import Foundation
import PDFKit
import Synchronization
import XCTest

@testable import Researchers

/// 공식 대용량 PDF와 혼합 배치의 원본 해시·순서·한도·취소·정리를 확인하고 수치를 남긴다.
final class DocumentLargeScanTests: XCTestCase {
  func testLargeScanOriginalHashesAndPageCounts() throws {
    let hashes = [
      "usgs-pp158": "c9cf7304b0704a98f1e85474aba740503893b05c6db8701e7d0f3a329359d624",
      "usgs-wsp158": "bb9d981fa9e82d15ccbc63fe902eddcaa729de1076e944e0ff92ef211b1f6fd9"
    ]
    for (name, hash) in hashes {
      let data = try Data(contentsOf: DocumentScanStressSupport.url(name))
      XCTAssertEqual(DocumentScanStressSupport.digest(data), hash)
      let document = try XCTUnwrap(PDFDocument(data: data))
      XCTAssertEqual(document.pageCount, name == "usgs-pp158" ? 204 : 42)
    }
  }

  func testOriginalLargeScanSerialAndParallel() async throws {
    executionTimeAllowance = 1_200
    let url = try DocumentScanStressSupport.url("usgs-pp158")
    var reference: DocumentParseResult?
    for workers in [1, 6] {
      let measurement = DocumentStressMeasurement()
      do {
        let result = try await DocumentParser.parse(.url(url), options: .init(
          maximumConcurrentPDFPages: workers)) { measurement.progress($0) }
        var report = await measurement.finish()
        report["requestedWorkers"] = workers
        report["result"] = DocumentScanStressSupport.row(result)
        try attach(report, name: "original-204-pages-workers-\(workers)")
        try DocumentScanStressSupport.check(result, pages: 204, workers: workers)
        XCTAssertTrue(result.fullText.lowercased().contains("general geology"))
        if let reference {
          XCTAssertEqual(result.blocks, reference.blocks)
          XCTAssertEqual(result.images, reference.images)
          XCTAssertEqual(result.warnings, reference.warnings)
        }
        reference = result
      } catch {
        try attach(await measurement.finish(), name: "original-failed-\(workers)")
        throw error
      }
    }
  }

  func testRasterOnlyRealScanHasOCRWithoutNativeText() async throws {
    executionTimeAllowance = 600
    let data = try DocumentScanStressSupport.rasterOnly()
    let document = try XCTUnwrap(PDFDocument(data: data))
    XCTAssertEqual(document.pageCount, 42)
    XCTAssertTrue((0..<42).allSatisfy { document.page(at: $0)?.string?.isEmpty != false })
    let measurement = DocumentStressMeasurement()
    do {
      let result = try await DocumentParser.parse(
        .data(data, fileName: "raster-only-wsp158.pdf")) { measurement.progress($0) }
      var report = await measurement.finish()
      report["inputBytes"] = data.count
      report["result"] = DocumentScanStressSupport.row(result)
      try attach(report, name: "raster-only-real-42-pages")
      try DocumentScanStressSupport.check(result, pages: 42, workers: 6)
      XCTAssertTrue(result.fullText.lowercased().contains("roswell"))
      XCTAssertTrue(result.blocks.contains { $0.kind == .imageOCR && $0.location.page == 42 })
      XCTAssertFalse(result.blocks.contains { $0.kind == .paragraph || $0.kind == .tableCell })
    } catch {
      try attach(await measurement.finish(), name: "raster-only-failed")
      throw error
    }
  }

  func testMixedBatchConcurrentDocumentsPreservesOutcomes() async throws {
    executionTimeAllowance = 1_200
    let inputs = try mixedInputs()
    for concurrency in [2, 4] {
      let measurement = DocumentStressMeasurement()
      do {
        let results = try await DocumentParser.parseBatch(inputs, options: .init(
          maximumConcurrentDocuments: concurrency, maximumConcurrentPDFPages: 6)) {
          measurement.progress($0)
        }
        var report = await measurement.finish()
        report["maximumConcurrentDocuments"] = concurrency
        report["results"] = try checkBatch(results, workers: 6)
        checkEvents(measurement, count: inputs.count, limit: concurrency)
        try attach(report, name: "mixed-batch-documents-\(concurrency)")
      } catch {
        try attach(await measurement.finish(), name: "batch-failed-\(concurrency)")
        throw error
      }
    }
  }

  func testLargeScanLimitsCancellationAndCleanup() async throws {
    let before = try DocumentScanStressSupport.temporaryDirectories()
    let url = try DocumentScanStressSupport.url("usgs-pp158")
    do {
      _ = try await DocumentParser.parse(.url(url), options: .init(maximumInputBytes: 1_024))
      XCTFail("Oversized original was opened")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .inputTooLarge) }
    let limited = try await DocumentParser.parse(.url(url), options: .init(
      maximumDocumentPages: 3, maximumEmbeddedImages: 1))
    try DocumentScanStressSupport.check(limited, pages: 3, workers: 6)
    XCTAssertTrue(limited.warnings.contains {
      $0.code == .resourceLimitReached && $0.location?.page == 4
    })
    let measurement = DocumentStressMeasurement()
    let started = Mutex(false)
    let operation = Task {
      try await DocumentParser.parseBatch(try mixedInputs(), options: .init(
        maximumConcurrentDocuments: 2)) { event in
        measurement.progress(event)
        if event.phase == .recognizingText { started.withLock { $0 = true } }
      }
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    while !started.withLock({ $0 }), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(started.withLock { $0 })
    let cancelledAt = ContinuousClock.now
    operation.cancel()
    do {
      _ = try await operation.value
      XCTFail("Cancelled batch completed")
    } catch {
      XCTAssertTrue(error is CancellationError || (error as? DocumentParsingError) == .cancelled)
    }
    var report = await measurement.finish()
    report["cancelToReturnSeconds"] = DocumentFootprint.seconds(cancelledAt.duration(to: .now))
    XCTAssertEqual(try DocumentScanStressSupport.temporaryDirectories(), before)
    report["temporaryDirectoriesAdded"] = 0
    try attach(report, name: "large-scan-limits-batch-cancellation")
  }

  private func mixedInputs() throws -> [DocumentInput] {
    let bundle = Bundle(for: Self.self)
    let resources = [
      ("real-docx-02-table_footnotes", "docx"), ("real-hwp-01-noori", "hwp"),
      ("real-jpeg-03-loancalc", "jpg")
    ]
    var inputs: [DocumentInput] = [
      .url(try DocumentScanStressSupport.url("usgs-pp158")),
      .url(try DocumentScanStressSupport.url("usgs-wsp158"))
    ]
    for (name, ext) in resources {
      let folder = ext == "jpg" ? "jpeg" : ext
      inputs.append(.url(try XCTUnwrap(bundle.url(
        forResource: name, withExtension: ext, subdirectory: "RealWorld/\(folder)"))))
    }
    inputs.append(.data(Data("BATCH SENTINEL 123".utf8), fileName: "sentinel.txt"))
    inputs.append(.data(Data("%PDF-1.7\nbroken".utf8), fileName: "broken.pdf"))
    return inputs
  }

  private func checkBatch(_ results: [DocumentBatchResult], workers: Int) throws
    -> [[String: Any]] {
    XCTAssertEqual(results.count, 7)
    let formats: [DocumentFormat] = [.pdf, .pdf, .docx, .hwp, .jpeg, .txt]
    var rows: [[String: Any]] = []
    for (index, outcome) in results.enumerated() {
      switch outcome {
      case .success(let result):
        guard index < formats.count else { XCTFail("Malformed PDF succeeded"); continue }
        XCTAssertEqual(result.format, formats[index])
        XCTAssertFalse(result.fullText.isEmpty)
        if index < 2 {
          try DocumentScanStressSupport.check(
            result, pages: index == 0 ? 204 : 42, workers: workers)
        }
        if index == 5 { XCTAssertEqual(result.fullText, "BATCH SENTINEL 123") }
        rows.append(DocumentScanStressSupport.row(result))
      case .failure(let error):
        XCTAssertEqual(index, 6)
        XCTAssertEqual(error, .malformedDocument)
        rows.append(["failure": String(describing: error)])
      }
    }
    return rows
  }

  private func checkEvents(_ measurement: DocumentStressMeasurement, count: Int, limit: Int) {
    let events = measurement.events.withLock { $0.map(\.1) }
    var active: Set<Int> = []
    var peak = 0
    for event in events {
      if event.phase == .identifying { active.insert(event.inputIndex) }
      peak = max(peak, active.count)
      if [.completed, .failed, .cancelled].contains(event.phase) {
        active.remove(event.inputIndex)
      }
    }
    XCTAssertTrue(active.isEmpty)
    XCTAssertGreaterThan(peak, 1)
    XCTAssertLessThanOrEqual(peak, limit)
    for index in 0..<count {
      let values = events.filter { $0.inputIndex == index }
      XCTAssertEqual(values.last?.phase, index == 6 ? .failed : .completed)
      XCTAssertEqual(values.map(\.fractionCompleted), values.map(\.fractionCompleted).sorted())
    }
  }

  private func attach(_ report: [String: Any], name: String) throws {
    let attachment = XCTAttachment(
      data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
      uniformTypeIdentifier: "public.json")
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
