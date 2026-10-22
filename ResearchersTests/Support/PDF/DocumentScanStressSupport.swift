import CryptoKit
import Foundation
import PDFKit
import Synchronization
import UIKit
import XCTest

@testable import Researchers

/// 대용량 원본 로딩·공통 검증·단계 수치·임시 폴더 확인을 모은다. 프로세스 메모리 표본과 작업 예약은 다른 지표다.
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

  static func check(_ result: DocumentParseResult, pages: Int, workers: Int) throws {
    let metrics = try XCTUnwrap(result.metrics)
    XCTAssertEqual(metrics.timings.filter {
      ["pdfPageOCR", "pdfPageOCRReuse"].contains($0.stage.rawValue)
    }.count, pages)
    XCTAssertLessThanOrEqual(metrics.peakInFlightPages, workers)
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

  static func row(_ result: DocumentParseResult) -> [String: Any] {
    var row: [String: Any] = [
      "format": result.format.rawValue, "textCharacters": result.fullText.count,
      "textSHA256": digest(Data(result.fullText.utf8)),
      "blocksSHA256": DocumentResultFingerprint.blocks(result.blocks),
      "imagesSHA256": DocumentResultFingerprint.images(result.images),
      "warningsSHA256": DocumentResultFingerprint.warnings(result.warnings),
      "blocks": result.blocks.count, "images": result.images.count,
      "imageBytes": result.images.reduce(0) { $0 + $1.pngData.count },
      "textPages": Set(result.blocks.compactMap { $0.location.page }).sorted(),
      "ocrBlocks": result.blocks.filter { $0.kind == .imageOCR }.count,
      "warnings": result.warnings.map {
        ["code": $0.code.rawValue, "page": $0.location?.page ?? 0] as [String: Any]
      }
    ]
    if let metrics = result.metrics {
      if let batch = metrics.batchScheduling {
        row["batchScheduling"] = [
          "peakInFlightPages": batch.peakInFlightPages,
          "peakEstimatedWorkingBytes": batch.peakEstimatedWorkingBytes,
          "activePagesAfterReturn": batch.activePages,
          "waitingRequestsAfterReturn": batch.waitingRequests
        ]
      }
      row["pdfWallSeconds"] = metrics.wallSeconds
      row["peakInFlightPages"] = metrics.peakInFlightPages
      row["peakEstimatedWorkingBytes"] = metrics.peakEstimatedWorkingBytes
      row["timings"] = metrics.timings.map {
        ["stage": $0.stage.rawValue, "page": $0.page ?? 0,
         "startOffsetSeconds": $0.startOffsetSeconds, "seconds": $0.seconds] as [String: Any]
      }
    }
    return row
  }

  static func temporaryDirectories() throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(
      atPath: FileManager.default.temporaryDirectory.path).filter {
        $0.hasPrefix("DocumentParsing-")
      })
  }
}

/// 수치는 본문 없이 보관한다. 20ms 샘플 최고값은 순간 최대 메모리의 근사치다.
nonisolated final class DocumentStressMeasurement: Sendable {
  let start = ContinuousClock.now
  let baseline = DocumentFootprint.bytes() ?? 0
  let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
  private let samples: Samples
  let events = Mutex<[(Double, DocumentProgress)]>([])
  let sampler: Task<Void, Error>

  init() {
    let samples = Samples()
    let origin = start
    self.samples = samples
    sampler = Task.detached {
      while !Task.isCancelled {
        if let value = DocumentFootprint.bytes() {
          let elapsed = DocumentFootprint.seconds(origin.duration(to: .now))
          samples.values.withLock { $0.append((elapsed, value)) }
        }
        try await Task.sleep(for: .milliseconds(20))
      }
    }
  }

  private final class Samples: Sendable {
    let values = Mutex<[(Double, UInt64)]>([])
  }

  func progress(_ event: DocumentProgress) {
    let elapsed = DocumentFootprint.seconds(start.duration(to: .now))
    events.withLock { $0.append((elapsed, event)) }
  }

  func finish() async -> [String: Any] {
    sampler.cancel()
    _ = await sampler.result
    let values = samples.values.withLock { $0 }
    let peak = values.max { $0.1 < $1.1 }
    return [
      "environment": DocumentFootprint.environment,
      "wallSeconds": DocumentFootprint.seconds(start.duration(to: .now)),
      "baselineFootprintBytes": baseline,
      "sampledPeakFootprintBytes": max(baseline, peak?.1 ?? 0),
      "sampledPeakOffsetSeconds": peak?.0 ?? 0,
      "footprintSamples": values.map { [$0.0, Double($0.1)] },
      "afterFootprintBytes": DocumentFootprint.bytes() ?? 0,
      "sampleIntervalMilliseconds": 20, "thermalBefore": thermalBefore,
      "thermalAfter": ProcessInfo.processInfo.thermalState.rawValue,
      "events": events.withLock { values in
        values.map { elapsed, event in
          ["seconds": elapsed, "index": event.inputIndex, "phase": event.phase.rawValue,
           "fraction": event.fractionCompleted] as [String: Any]
        }
      }
    ]
  }
}
