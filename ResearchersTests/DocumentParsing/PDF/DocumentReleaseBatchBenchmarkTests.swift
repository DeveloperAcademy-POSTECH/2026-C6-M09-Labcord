import Foundation
import XCTest

@testable import Researchers

/// 실제 한국어·영문 혼합 배치의 Release 측정이다. 냉각 대기가 있는 비교 실행과 계측용 진단 실행을 구분한다.
final class DocumentReleaseBatchBenchmarkTests: XCTestCase {
  func testReleaseMixedBatch() async throws { try await benchmark(korean: false) }

  func testKoreanMixedBatch() async throws { try await benchmark(korean: true) }

  func testKoreanMixedBatchConservativeMemory() async throws {
    try await benchmark(korean: true, workingMemoryBytes: 128 * 1024 * 1024)
  }

  /// Instruments가 모델 초기화 전 붙을 시간을 준다. 성능 비교 표본으로 사용하지 않는다.
  func testProfileEnglishBatch() async throws {
    try await Task.sleep(for: .seconds(15))
    try await benchmark(korean: false, waitForCooling: false)
  }

  func testProfileEnglishHeapRelief() async throws {
    executionTimeAllowance = 1_200
    let inputs = try inputs(korean: false)
    let measurement = DocumentStressMeasurement()
    let probe = DocumentHeapReliefProbe()
    do {
      let results = try await DocumentParser.parseBatch(inputs, options: .init(
        maximumConcurrentDocuments: 4, maximumConcurrentPDFPages: 6)) {
        measurement.progress($0)
        probe.progress($0)
      }
      var report = await measurement.finish()
      report["configuration"] = configuration
      report["diagnosticProfile"] = true
      report["scenario"] = "english-mixed-7"
      report["heapReliefProbe"] = probe.report
      report["results"] = try resultRows(results, korean: false)
      let attachment = XCTAttachment(
        data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
        uniformTypeIdentifier: "public.json")
      attachment.name = "release-mixed-batch"
      attachment.lifetime = .keepAlways
      add(attachment)
    } catch {
      _ = await measurement.finish()
      throw error
    }
  }

  private func benchmark(
    korean: Bool, workingMemoryBytes: Int = 256 * 1024 * 1024, waitForCooling: Bool = true
  ) async throws {
    executionTimeAllowance = 1_200
    let cooldown = waitForCooling ? try await waitForNominalThermalState() : 0
    let before = try DocumentScanStressSupport.temporaryDirectories()
    let inputs = try inputs(korean: korean)
    let measurement = DocumentStressMeasurement()
    do {
      let results = try await DocumentParser.parseBatch(inputs, options: .init(
        maximumConcurrentDocuments: 4, maximumConcurrentPDFPages: 6,
        pdfWorkingMemoryTargetBytes: workingMemoryBytes)) {
        measurement.progress($0)
      }
      var report = await measurement.finish()
      report["cooldownSeconds"] = cooldown
      report["configuration"] = configuration
      report["diagnosticProfile"] = !waitForCooling
      report["pdfWorkingMemoryTargetBytes"] = workingMemoryBytes
      report["date"] = ISO8601DateFormatter().string(from: Date())
      report["scenario"] = korean ? "korean-mixed-7" : "english-mixed-7"
      report["results"] = try resultRows(results, korean: korean)
      XCTAssertEqual(results.count, 7)
      XCTAssertEqual(try DocumentScanStressSupport.temporaryDirectories(), before)
      let attachment = XCTAttachment(
        data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
        uniformTypeIdentifier: "public.json")
      attachment.name = "release-mixed-batch"
      attachment.lifetime = .keepAlways
      add(attachment)
    } catch {
      _ = await measurement.finish()
      throw error
    }
  }

  private var configuration: String {
    #if DEBUG
    "Debug"
    #else
    "Release"
    #endif
  }

  private func waitForNominalThermalState() async throws -> Double {
    let start = ContinuousClock.now
    let deadline = start.advanced(by: .seconds(360))
    while ProcessInfo.processInfo.thermalState != .nominal, ContinuousClock.now < deadline {
      try await Task.sleep(for: .seconds(5))
    }
    return DocumentFootprint.seconds(start.duration(to: .now))
  }

  private func resultRows(_ results: [DocumentBatchResult], korean: Bool) throws
    -> [[String: Any]] {
    let formats: [DocumentFormat] = [.pdf, .pdf, .docx, .hwp, .jpeg, .txt]
    return try results.enumerated().map { index, outcome in
      switch outcome {
      case .success(let result):
        guard index < formats.count else { XCTFail("Malformed PDF succeeded"); return [:] }
        XCTAssertEqual(result.format, formats[index])
        if index < 2 {
          let pages = index == 0 ? (korean ? 125 : 204) : 42
          try DocumentScanStressSupport.check(result, pages: pages, workers: 6)
        }
        if index == 0 && korean { DocumentKoreanScanAssertions.verifyResult(result) }
        if index == 5 { XCTAssertEqual(result.fullText, "BATCH SENTINEL 123") }
        XCTAssertFalse(result.fullText.isEmpty)
        return DocumentScanStressSupport.row(result)
      case .failure(let error):
        XCTAssertEqual(index, 6)
        XCTAssertEqual(error, .malformedDocument)
        return ["failure": String(describing: error)]
      }
    }
  }

  private func inputs(korean: Bool) throws -> [DocumentInput] {
    if korean {
      try DocumentKoreanScanAssertions.verifyOriginal(DocumentScanStressSupport.url("korean-1992"))
    }
    var inputs: [DocumentInput] = [
      .url(try DocumentScanStressSupport.url(korean ? "korean-1992" : "usgs-pp158")),
      .url(try DocumentScanStressSupport.url("usgs-wsp158"))
    ]
    for (name, ext, folder) in [
      ("real-docx-02-table_footnotes", "docx", "docx"),
      ("real-hwp-01-noori", "hwp", "hwp"), ("real-jpeg-03-loancalc", "jpg", "jpeg")
    ] {
      inputs.append(.url(try XCTUnwrap(Bundle(for: Self.self).url(
        forResource: name, withExtension: ext, subdirectory: "RealWorld/\(folder)"))))
    }
    inputs.append(.data(Data("BATCH SENTINEL 123".utf8), fileName: "sentinel.txt"))
    inputs.append(.data(Data("%PDF-1.7\nbroken".utf8), fileName: "broken.pdf"))
    return inputs
  }
}
