import CoreGraphics
import CoreML
import Foundation
import Vision
import XCTest

@testable import Researchers

/// 같은 이미지에서 대비·실행 장치 설정에 따른 OCR 후보를 비교하는 진단용 검사다. 앱의 기본 설정을 바꾸지 않는다.
final class DocumentOCRDeviceTests: XCTestCase {
  func testCompareContrastThresholds() throws {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: "real-jpeg-03-loancalc", withExtension: "jpg",
      subdirectory: "RealWorld/jpeg"))
    let decoded = try DocumentImageDecoder.decode(
      Data(contentsOf: url), maximumPixels: 1_000_000)
    var rows: [[String: Any]] = []
    for cutoff: UInt8 in [120, 130, 140, 145, 150, 155, 160, 165] {
      let image = try XCTUnwrap(DocumentNumericOCR.threshold(decoded.image, cutoff: cutoff))
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.recognitionLanguages = ["ko-KR", "en-US"]
      request.automaticallyDetectsLanguage = true
      request.usesLanguageCorrection = true
      try VNImageRequestHandler(cgImage: image, orientation: decoded.orientation)
        .perform([request])
      let values = (request.results ?? []).filter {
        $0.boundingBox.midX > 0.47 && $0.boundingBox.midX < 0.58
          && $0.boundingBox.midY < 0.36
      }.sorted { $0.boundingBox.midY > $1.boundingBox.midY }.compactMap { observation in
        observation.topCandidates(1).first.map {
          ["text": $0.string, "confidence": $0.confidence] as [String: Any]
        }
      }
      rows.append(["cutoff": cutoff, "values": values])
    }
    let attachment = XCTAttachment(
      data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
      uniformTypeIdentifier: "public.json")
    attachment.name = "ocr-device-contrast-comparison"
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertEqual(rows.count, 8)
  }

  func testCompareCPUAndAutomaticRecognition() throws {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: "real-jpeg-03-loancalc", withExtension: "jpg",
      subdirectory: "RealWorld/jpeg"))
    let decoded = try DocumentImageDecoder.decode(
      Data(contentsOf: url), maximumPixels: 1_000_000)
    var rows: [[String: Any]] = []
    for threshold in [false, true] {
      let image = threshold ? try XCTUnwrap(DocumentNumericOCR.threshold(decoded.image))
        : decoded.image
      for cpuOnly in [false, true] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        if cpuOnly {
          for (stage, devices) in try request.supportedComputeStageDevices {
            if let cpu = devices.first(where: { if case .cpu = $0 { true } else { false } }) {
              request.setComputeDevice(cpu, for: stage)
            }
          }
        }
        let start = ContinuousClock.now
        try VNImageRequestHandler(cgImage: image, orientation: decoded.orientation)
          .perform([request])
        let elapsed = start.duration(to: .now)
        let values = (request.results ?? []).filter {
          $0.boundingBox.midX > 0.47 && $0.boundingBox.midX < 0.58
            && $0.boundingBox.midY < 0.36
        }.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
          .compactMap { $0.topCandidates(1).first?.string }
        rows.append([
          "threshold": threshold, "cpuOnly": cpuOnly, "values": values,
          "seconds": Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        ])
      }
    }
    let attachment = XCTAttachment(
      data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
      uniformTypeIdentifier: "public.json")
    attachment.name = "ocr-compute-device-comparison"
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertEqual(rows.count, 4)
  }
}
