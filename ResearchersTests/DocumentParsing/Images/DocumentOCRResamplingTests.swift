import CoreGraphics
import Foundation
import ImageIO
import Vision
import XCTest

@testable import Researchers

/// 임계값·부분 영역·리샘플링 후보를 별도로 비교한다. 진단 결과가 곧 제품 채택 설정은 아니다.
final class DocumentOCRResamplingTests: XCTestCase {
  func testCompareThresholdAndCandidates() throws {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: "real-jpeg-03-loancalc", withExtension: "jpg",
      subdirectory: "RealWorld/jpeg"))
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var rows: [[String: Any]] = []
    for threshold in [0, 100, 150, 180, 210] {
      var bytes = [UInt8](repeating: 255, count: image.width * image.height * 4)
      let raster: CGImage = try bytes.withUnsafeMutableBytes { buffer in
        let context = try XCTUnwrap(CGContext(
          data: buffer.baseAddress, width: image.width, height: image.height,
          bitsPerComponent: 8, bytesPerRow: image.width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        if threshold > 0 {
          for offset in stride(from: 0, to: buffer.count, by: 4) {
            let value: UInt8 = Int(buffer[offset]) < threshold ? 0 : 255
            buffer[offset] = value
            buffer[offset + 1] = value
            buffer[offset + 2] = value
          }
        }
        return try XCTUnwrap(context.makeImage())
      }
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.recognitionLanguages = ["ko-KR", "en-US"]
      request.automaticallyDetectsLanguage = true
      try VNImageRequestHandler(cgImage: raster).perform([request])
      let values = (request.results ?? []).filter {
        $0.boundingBox.midX > 0.47 && $0.boundingBox.midX < 0.58
          && $0.boundingBox.midY < 0.36
      }.sorted { $0.boundingBox.midY > $1.boundingBox.midY }.map {
        $0.topCandidates(5).map { candidate in
          ["text": candidate.string, "confidence": candidate.confidence] as [String: Any]
        }
      }
      rows.append(["threshold": threshold, "values": values])
    }
    let attachment = XCTAttachment(
      data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
      uniformTypeIdentifier: "public.json")
    attachment.name = "ocr-threshold-comparison"
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertEqual(rows.count, 5)
  }

  func testCompareIsolatedCurrencyRegions() throws {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: "real-jpeg-03-loancalc", withExtension: "jpg",
      subdirectory: "RealWorld/jpeg"))
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var rows: [[String: Any]] = []
    for (index, originY) in [218, 258, 278].enumerated() {
      let bounds = CGRect(x: 280, y: originY, width: 64, height: 23)
      let crop = try XCTUnwrap(image.cropping(to: bounds))
      for scale in [2, 4, 6] {
        let context = try XCTUnwrap(CGContext(
          data: nil, width: 84 * scale, height: 43 * scale,
          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.interpolationQuality = .high
        context.draw(crop, in: CGRect(x: 10 * scale, y: 10 * scale,
                                      width: 64 * scale, height: 23 * scale))
        let raster = try XCTUnwrap(context.makeImage())
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: raster).perform([request])
        rows.append(["region": index, "scale": scale,
                     "values": (request.results ?? []).compactMap {
                       $0.topCandidates(1).first?.string
                     }])
      }
    }
    let attachment = XCTAttachment(
      data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
      uniformTypeIdentifier: "public.json")
    attachment.name = "ocr-isolated-comparison"
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertEqual(rows.count, 9)
  }

  func testCompareSmallScreenshotResampling() throws {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: "real-jpeg-03-loancalc", withExtension: "jpg",
      subdirectory: "RealWorld/jpeg"))
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var rows: [[String: Any]] = []
    for scale in [1, 2, 3] {
      let context = try XCTUnwrap(CGContext(
        data: nil, width: image.width * scale, height: image.height * scale,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
      let raster = try XCTUnwrap(context.makeImage())
      for correction in [true, false] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = correction
        let start = ContinuousClock.now
        try VNImageRequestHandler(cgImage: raster).perform([request])
        let elapsed = start.duration(to: .now)
        let values = (request.results ?? []).filter {
          $0.boundingBox.midX > 0.47 && $0.boundingBox.midX < 0.58
            && $0.boundingBox.midY < 0.36
        }.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
          .compactMap { $0.topCandidates(1).first?.string }
        rows.append([
          "scale": scale, "languageCorrection": correction, "values": values,
          "seconds": Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        ])
      }
    }
    let attachment = XCTAttachment(
      data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
      uniformTypeIdentifier: "public.json")
    attachment.name = "ocr-resampling-comparison"
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertEqual(rows.count, 6)
  }
}
