import CoreGraphics
import Foundation
import ImageIO
import Vision

nonisolated enum DocumentOCR {
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

  static func makeRequest() -> VNRecognizeTextRequest {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["ko-KR", "en-US"]
    request.automaticallyDetectsLanguage = true
    return request
  }

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
