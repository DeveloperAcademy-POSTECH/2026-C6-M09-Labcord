import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Vision

/// 호출 하나의 작업창 안에서만 공유한다. 대여한 세션은 한 OCR 호출만 사용한다.
/// 실행 동시성은 상위 문서/PDF 작업창이 제한하고, 완료한 세션은 최대 2개만 보관한다.
/// 풀은 parse 또는 parseBatch 호출 범위를 벗어나 전역 캐시로 남지 않는다.
/// 한 세션의 요청·핸들러는 함께 잠그지만 서로 다른 세션은 병렬로 OCR할 수 있다.
nonisolated final class DocumentOCRSessionPool: Sendable {
  private struct RecognitionState {
    let handler = VNSequenceRequestHandler()
    let request = DocumentOCR.makeRequest()
  }

  private final class Session: Sendable {
    private let state = Mutex(RecognitionState())

    func perform(
      image: CGImage, orientation: CGImagePropertyOrientation,
      convert: ([VNRecognizedTextObservation]) throws -> [DocumentBlock]
    ) throws -> [DocumentBlock] {
      try state.withLock { value in
        try Task.checkCancellation()
        try value.handler.perform([value.request], on: image, orientation: orientation)
        try Task.checkCancellation()
        return try convert(value.request.results ?? [])
      }
    }
  }

  private let idle = Mutex<[Session]>([])

  var cachedSessionCount: Int { idle.withLock { $0.count } }

  /// 대여·반환 때만 풀을 잠근다. 인식이 실패하거나 취소되면 세션을 유휴 목록에 돌려놓지 않는다.
  func perform(
    image: CGImage, orientation: CGImagePropertyOrientation,
    convert: ([VNRecognizedTextObservation]) throws -> [DocumentBlock]
  ) throws -> [DocumentBlock] {
    let session = idle.withLock { $0.popLast() } ?? Session()
    // 실패·취소한 핸들러는 재사용하지 않고 해제한다.
    let result = try session.perform(image: image, orientation: orientation, convert: convert)
    idle.withLock { if $0.count < 2 { $0.append(session) } }
    return result
  }
}
