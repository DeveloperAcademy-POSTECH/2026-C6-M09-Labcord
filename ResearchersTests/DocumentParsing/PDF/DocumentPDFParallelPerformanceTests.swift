import Foundation
import Synchronization
import XCTest

@testable import Researchers

/// 작업창 크기와 실행 순서를 바꿔 PDF 단계별 시간을 기록한다. 겹치는 단계 시간을 합쳐 전체 시간으로 해석하지 않는다.
final class DocumentPDFParallelPerformanceTests: XCTestCase {
  func testCompareSerialAndParallelStageTimesOnHundredPages() async throws {
    let data = DocumentPDFParallelFixture.hundredPages()
    var runs: [[String: Any]] = []
    let orders = [[1, 2, 4, 6], [6, 4, 2, 1], [2, 6, 1, 4]]
    for (round, order) in orders.enumerated() {
      for workers in order {
        runs.append(try await run(data, round: round, workers: workers))
      }
    }
    try attach([
      "environment": DocumentFootprint.environment,
      "activeProcessorCount": ProcessInfo.processInfo.activeProcessorCount,
      "pages": 100, "inputBytes": data.count, "runs": runs
    ], name: "pdf-parallel-stage-comparison")
  }

  func testMixedDocumentStageTimings() async throws {
    let data = try DocumentPDFParallelFixture.make()
    var rows: [[String: Any]] = []
    for workers in [1, 2, 6] {
      let result = try await DocumentParser.parse(
        .data(data, fileName: "mixed.pdf"), options: .init(maximumConcurrentPDFPages: workers))
      let metrics = try XCTUnwrap(result.metrics)
      XCTAssertEqual(result.images.count, 4)
      XCTAssertTrue(result.fullText.contains("IMAGE"))
      XCTAssertTrue(metrics.timings.contains { $0.stage == .pdfImageOCR })
      var sums: [String: Double] = [:]
      for value in metrics.timings { sums[value.stage.rawValue, default: 0] += value.seconds }
      rows.append([
        "requestedWorkers": workers, "wallSeconds": metrics.wallSeconds,
        "peakInFlightPages": metrics.peakInFlightPages,
        "stageSumsSeconds": sums, "timings": timingRows(metrics)
      ])
    }
    try attach([
      "environment": DocumentFootprint.environment, "pages": 6, "runs": rows
    ], name: "pdf-mixed-stage-comparison")
  }

  private func run(_ data: Data, round: Int, workers: Int) async throws -> [String: Any] {
    let samples = Mutex<[UInt64]>([])
    let before = try XCTUnwrap(DocumentFootprint.bytes())
    let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
    let sampler = Task.detached {
      while !Task.isCancelled {
        if let value = DocumentFootprint.bytes() { samples.withLock { $0.append(value) } }
        try await Task.sleep(for: .milliseconds(20))
      }
    }
    let start = ContinuousClock.now
    let result: DocumentParseResult
    do {
      result = try await DocumentParser.parse(
        .data(data, fileName: "100-pages.pdf"),
        options: .init(maximumConcurrentPDFPages: workers))
    } catch {
      sampler.cancel()
      _ = await sampler.result
      throw error
    }
    let elapsed = DocumentFootprint.seconds(start.duration(to: .now))
    sampler.cancel()
    _ = await sampler.result
    let metrics = try XCTUnwrap(result.metrics)
    XCTAssertEqual(Set(result.blocks.compactMap { $0.location.page }).count, 100)
    XCTAssertEqual(result.blocks.count, 100)
    XCTAssertTrue(result.fullText.contains("Page 100 PERFORMANCE 123"))
    var stageSums: [String: Double] = [:]
    for value in metrics.timings { stageSums[value.stage.rawValue, default: 0] += value.seconds }
    var row: [String: Any] = [
      "round": round, "requestedWorkers": workers, "wallSeconds": elapsed,
      "pdfWallSeconds": metrics.wallSeconds, "peakInFlightPages": metrics.peakInFlightPages,
      "peakEstimatedWorkingBytes": metrics.peakEstimatedWorkingBytes,
      "baselineFootprintBytes": before,
      "sampledPeakFootprintBytes": samples.withLock { $0.max() ?? before },
      "afterFootprintBytes": try XCTUnwrap(DocumentFootprint.bytes()),
      "stageSumsSeconds": stageSums, "thermalBefore": thermalBefore,
      "thermalAfter": ProcessInfo.processInfo.thermalState.rawValue
    ]
    if round == 0 {
      row["timings"] = timingRows(metrics)
    }
    return row
  }

  private func timingRows(_ metrics: DocumentParsingMetrics) -> [[String: Any]] {
    metrics.timings.map { value in
      var item: [String: Any] = [
        "stage": value.stage.rawValue, "startOffsetSeconds": value.startOffsetSeconds,
        "seconds": value.seconds
      ]
      if let page = value.page { item["page"] = page }
      return item
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
