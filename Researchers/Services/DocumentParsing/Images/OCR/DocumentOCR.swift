import CoreGraphics
import Foundation
import ImageIO
import Vision

/// 모든 형식에서 공통으로 사용하는 온디바이스 Vision OCR이다.
/// 한영 인식 결과를 좌상단 기준 좌표와 읽기 순서가 있는 블록으로 변환한다.
nonisolated enum DocumentOCR {
  /// parse·parseBatch가 만든 풀을 자식 작업에 전달한다. 전역으로 모든 문서의 세션을 공유하지 않는다.
  @TaskLocal static var sessions: DocumentOCRSessionPool?

  static func recognize(
    image: CGImage,
    orientation: CGImagePropertyOrientation,
    location: DocumentLocation = DocumentLocation()
  ) throws -> [DocumentBlock] {
    // 페이지 안의 다음 OCR 호출까지 Vision 임시 객체를 보유하지 않는다.
    return try autoreleasepool {
      try Task.checkCancellation()
      if let sessions {
        return try sessions.perform(image: image, orientation: orientation) {
          try blocks($0, image: image, orientation: orientation, location: location)
        }
      }
      let request = makeRequest()
      let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
      try handler.perform([request])
      try Task.checkCancellation()
      return try blocks(request.results ?? [], image: image, orientation: orientation,
                        location: location)
    }
  }

  /// 새 핸들러와 재사용 핸들러 모두 같은 한영·정확도·언어 보정 설정을 사용한다.
  static func makeRequest() -> VNRecognizeTextRequest {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["ko-KR", "en-US"]
    request.automaticallyDetectsLanguage = true
    return request
  }

  /// Vision의 좌하단 원점을 좌상단으로 뒤집는다. 부분 그림의 페이지 좌표 변환은 호출 측이 담당한다.
  private static func blocks(
    _ source: [VNRecognizedTextObservation], image: CGImage,
    orientation: CGImagePropertyOrientation, location: DocumentLocation
  ) throws -> [DocumentBlock] {
    let enhanced = try DocumentNumericOCR.refine(
      image: image, orientation: orientation, observations: source)
    let observations = source.sorted {
      if $0.boundingBox.midY != $1.boundingBox.midY {
        return $0.boundingBox.midY > $1.boundingBox.midY
      }
      return $0.boundingBox.minX < $1.boundingBox.minX
    }
    return observations.enumerated().compactMap { order, observation in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      var located = location
      let bounds = observation.boundingBox
      located.bounds = CGRect(
        x: bounds.minX,
        y: 1 - bounds.maxY,
        width: bounds.width,
        height: bounds.height
      )
      return DocumentBlock(
        kind: .imageOCR,
        text: enhanced[observation.uuid]?.text ?? candidate.string,
        readingOrder: order,
        location: located,
        ocrConfidence: enhanced[observation.uuid]?.confidence ?? candidate.confidence,
        ocrOriginalText: enhanced[observation.uuid] == nil ? nil : candidate.string
      )
    }
  }
}
