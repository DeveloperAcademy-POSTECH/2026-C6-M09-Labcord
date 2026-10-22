import Darwin
import Foundation
import Synchronization
import UIKit
import XCTest

@testable import Researchers

/// 생성한 100페이지 PDF의 시간·메모리와 취소·정리 수치를 기록한다. 단일 실행을 기기 전체의 성능 보장치로 사용하지 않는다.
final class DocumentPerformanceTests: XCTestCase {
  func testHundredPagePDFReportsTimeAndSampledFootprint() async throws {
    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
    let data = renderer.pdfData { context in
      for page in 1...100 {
        context.beginPage()
        ("Page \(page) PERFORMANCE 123" as NSString).draw(
          at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
      }
    }
    let samples = Mutex<[UInt64]>([])
    let baseline = try XCTUnwrap(DocumentFootprint.bytes())
    let sampler = Task.detached {
      while !Task.isCancelled {
        if let value = DocumentFootprint.bytes() { samples.withLock { $0.append(value) } }
        try await Task.sleep(for: .milliseconds(20))
      }
    }
    var rows: [[String: Any]] = []
    do {
      for iteration in 0..<5 {
        let start = ContinuousClock.now
        let result = try await DocumentParser.parse(.data(data, fileName: "100-pages.pdf"))
        let duration = start.duration(to: .now)
        XCTAssertEqual(Set(result.blocks.compactMap { $0.location.page }).count, 100)
        XCTAssertTrue(result.fullText.contains("Page 100 PERFORMANCE 123"))
        rows.append([
          "iteration": iteration, "seconds": DocumentFootprint.seconds(duration),
          "blocks": result.blocks.count
        ])
      }
    } catch {
      sampler.cancel()
      _ = await sampler.result
      throw error
    }
    sampler.cancel()
    _ = await sampler.result
    let report: [String: Any] = [
      "environment": DocumentFootprint.environment, "inputBytes": data.count, "pages": 100,
      "baselineFootprintBytes": baseline,
      "sampledPeakFootprintBytes": samples.withLock { $0.max() ?? baseline },
      "afterFootprintBytes": try XCTUnwrap(DocumentFootprint.bytes()),
      "sampleIntervalMilliseconds": 20, "runs": rows
    ]
    try attach(report, name: "hundred-page-performance")
  }

  func testCancellationLatencyAndOfficeTemporaryCleanup() async throws {
    let before = try temporaryDirectories()
    let url = try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: "real-hwpx-02-noori", withExtension: "hwpx", subdirectory: "RealWorld/hwpx"))
    _ = try await DocumentParser.parse(.url(url))
    let office = try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: "LegacySample", withExtension: "doc"))
    _ = try await DocumentParser.parse(.url(office))
    let malformed = DocumentArchiveFixtureBuilder.make([
      ("word/document.xml", Data("<broken".utf8))
    ])
    do {
      _ = try await DocumentParser.parse(.data(malformed, fileName: "broken.docx"))
      XCTFail("Malformed Office document completed")
    } catch { XCTAssertFalse(error is CancellationError) }
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("CANCEL LATENCY 123"))
    let data = try DocumentImageFixtures.tiff(Array(repeating: (image, .up), count: 20))
    let started = Mutex(false)
    let task = Task {
      try await DocumentParser.parse(.data(data, fileName: "twenty-frames.tiff")) { event in
        if event.phase == .recognizingText { started.withLock { $0 = true } }
      }
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !started.withLock({ $0 }), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertTrue(started.withLock { $0 })
    // 즉시 경계 취소와 구분해 Vision 실행 중을 겨냥하여 취소한다.
    try await Task.sleep(for: .milliseconds(20))
    let requestTime = ContinuousClock.now
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Cancelled TIFF completed")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .cancelled) }
    let seconds = DocumentFootprint.seconds(requestTime.duration(to: .now))
    XCTAssertEqual(try temporaryDirectories(), before)
    try attach([
      "environment": DocumentFootprint.environment, "cancelToReturnSeconds": seconds,
      "frames": 20, "temporaryDirectoriesAdded": 0
    ], name: "cancellation-and-cleanup")
  }

  private func temporaryDirectories() throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(
      atPath: FileManager.default.temporaryDirectory.path).filter {
        $0.hasPrefix("DocumentParsing-")
      })
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

nonisolated enum DocumentFootprint {
  static var environment: String {
    #if targetEnvironment(simulator)
    "simulator"
    #else
    "physical-device"
    #endif
  }

  static func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }

  static func bytes() -> UInt64? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size
      / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return status == KERN_SUCCESS ? info.phys_footprint : nil
  }
}
