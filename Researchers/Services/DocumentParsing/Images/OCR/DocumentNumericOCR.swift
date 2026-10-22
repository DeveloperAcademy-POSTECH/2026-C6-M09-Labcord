import CoreGraphics
import Foundation
import ImageIO
import Vision

/// 작은 숫자 OCR의 통화 기호 혼동을 별도 픽셀 인식으로 재확인한다.
/// 작은 이미지의 낮은 신뢰도 통화 기호만 제한적으로 재인식한다.
/// 문자열을 임의 치환하지 않고, 숫자 부분이 같은 더 나은 인식 후보가 있을 때만 채택한다.
nonisolated enum DocumentNumericOCR {
  struct Candidate {
    let text: String
    let confidence: Float
  }

  static func refine(
    image: CGImage, orientation: CGImagePropertyOrientation,
    observations: [VNRecognizedTextObservation]
  ) throws -> [UUID: Candidate] {
    guard image.width <= 1_000_000 / max(1, image.height) else { return [:] }
    let orientedHeight: Int
    switch orientation {
    case .left, .leftMirrored, .right, .rightMirrored: orientedHeight = image.width
    default: orientedHeight = image.height
    }
    let targets = observations.filter { shouldRefine($0, height: orientedHeight) }
    guard !targets.isEmpty else { return [:] }
    var result: [UUID: Candidate] = [:]
    // 고정 투영 하나에만 의존하지 않고 밝기 임계값을 좁은 범위에서 재확인한다.
    for cutoff: UInt8 in [150, 140, 160] {
      guard targets.contains(where: { result[$0.uuid] == nil }) else { break }
      try Task.checkCancellation()
      guard let raster = threshold(image, cutoff: cutoff) else { continue }
      let alternatives = try recognize(raster, orientation: orientation)
      for target in targets where result[target.uuid] == nil {
        guard let original = target.topCandidates(1).first else { continue }
        let match = alternatives.max {
          overlap($0.boundingBox, target.boundingBox) < overlap($1.boundingBox, target.boundingBox)
        }
        guard let match, overlap(match.boundingBox, target.boundingBox) >= 0.5,
          let alternative = match.topCandidates(1).first,
          accepts(original.string, confidence: original.confidence,
                  alternative: alternative.string, alternativeConfidence: alternative.confidence)
        else { continue }
        result[target.uuid] = Candidate(
          text: alternative.string, confidence: alternative.confidence)
      }
    }
    return result
  }

  private static func shouldRefine(
    _ observation: VNRecognizedTextObservation, height: Int
  ) -> Bool {
    guard let text = observation.topCandidates(1).first else { return false }
    return text.confidence <= 0.65 && observation.boundingBox.height * CGFloat(height) <= 24
      && isAmbiguous(text.string)
  }

  private static func recognize(
    _ image: CGImage, orientation: CGImagePropertyOrientation
  ) throws -> [VNRecognizedTextObservation] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ko-KR", "en-US"]
    request.automaticallyDetectsLanguage = true
    request.usesLanguageCorrection = true
    do {
      try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
    } catch {
      try Task.checkCancellation()
      return []
    }
    try Task.checkCancellation()
    return request.results ?? []
  }

  /// 대안이 실제로 $를 인식했고 나머지 숫자·구분자와 신뢰도 조건까지 맞는 경우만 보완한다.
  static func accepts(
    _ original: String, confidence: Float, alternative: String, alternativeConfidence: Float
  ) -> Bool {
    isAmbiguous(original) && alternative.first == "$"
      && original.dropFirst() == alternative.dropFirst()
      && alternativeConfidence >= confidence
  }

  private static func isAmbiguous(_ text: String) -> Bool {
    text.range(of: #"^[S5][0-9,]*\.[0-9]{2}$"#, options: .regularExpression) != nil
  }

  private static func overlap(_ first: CGRect, _ second: CGRect) -> CGFloat {
    let intersection = first.intersection(second)
    guard !intersection.isNull else { return 0 }
    let area = intersection.width * intersection.height
    return area / max(0.000001, first.width * first.height + second.width * second.height - area)
  }

  /// 원본을 수정하지 않고 별도 흑백 인식 입력을 만든다. 대상 이미지는 refine에서 크기를 제한한다.
  static func threshold(_ image: CGImage, cutoff: UInt8 = 150) -> CGImage? {
    var bytes = [UInt8](repeating: 255, count: image.width * image.height * 4)
    return bytes.withUnsafeMutableBytes { buffer in
      guard let context = CGContext(
        data: buffer.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return nil }
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      for offset in stride(from: 0, to: buffer.count, by: 4) {
        // 색 성분의 한 투영으로 만든 별도 인식 입력이며 원본 픽셀은 바꾸지 않는다.
        let value: UInt8 = buffer[offset] < cutoff ? 0 : 255
        buffer[offset] = value
        buffer[offset + 1] = value
        buffer[offset + 2] = value
      }
      return context.makeImage()
    }
  }
}
