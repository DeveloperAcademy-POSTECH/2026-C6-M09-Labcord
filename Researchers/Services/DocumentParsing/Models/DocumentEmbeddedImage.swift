import Foundation
import ImageIO

/// 내장 이미지가 표시된 영역의 PNG 래스터와 원본 문서 위치입니다.
nonisolated public struct DocumentEmbeddedImage: Sendable, Equatable {
  public var id: String
  public var pngData: Data
  public var location: DocumentLocation
  public var sourceDescription: String?
  public var orientation: CGImagePropertyOrientation

  public init(
    id: String, pngData: Data, location: DocumentLocation,
    orientation: CGImagePropertyOrientation = .up,
    sourceDescription: String? = nil
  ) {
    self.sourceDescription = sourceDescription
    self.id = id
    self.pngData = pngData
    self.location = location
    self.orientation = orientation
  }
}
