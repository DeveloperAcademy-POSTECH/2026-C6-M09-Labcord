import Foundation
import XCTest

@testable import Researchers

/// 공식 한국어 125쪽 스캔을 끝까지 읽고 일부 수동 기준 문구를 확인한다. 전체 문자 오류율 검사는 아니다.
final class DocumentKoreanScanTests: XCTestCase {
  func testOriginalKoreanScanReleasePerformanceAndAnchors() async throws {
    executionTimeAllowance = 900
    let start = ContinuousClock.now
    let deadline = start.advanced(by: .seconds(360))
    while ProcessInfo.processInfo.thermalState != .nominal, ContinuousClock.now < deadline {
      try await Task.sleep(for: .seconds(5))
    }
    let cooldown = DocumentFootprint.seconds(start.duration(to: .now))
    let url = try DocumentScanStressSupport.url("korean-1992")
    try DocumentKoreanScanAssertions.verifyOriginal(url)
    let measurement = DocumentStressMeasurement()
    do {
      let result = try await DocumentParser.parse(
        .url(url), options: .init(maximumConcurrentPDFPages: 6)) { measurement.progress($0) }
      var report = await measurement.finish()
      report["cooldownSeconds"] = cooldown
      #if DEBUG
      report["configuration"] = "Debug"
      #else
      report["configuration"] = "Release"
      #endif
      report["date"] = ISO8601DateFormatter().string(from: Date())
      report["result"] = DocumentScanStressSupport.row(result)
      let attachment = XCTAttachment(
        data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
        uniformTypeIdentifier: "public.json")
      attachment.name = "korean-original-125-pages"
      attachment.lifetime = .keepAlways
      add(attachment)
      try DocumentScanStressSupport.check(result, pages: 125, workers: 6)
      DocumentKoreanScanAssertions.verifyResult(result)
    } catch {
      _ = await measurement.finish()
      throw error
    }
  }
}
