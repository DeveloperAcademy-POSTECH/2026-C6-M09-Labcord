import Foundation
import ImageIO

/// 내장 이미지가 표시된 영역의 PNG 래스터와 원본 문서 위치입니다.
/// 이 데이터는 추출된 그림이며 OCR 문구는 result.blocks의 imageOCR 블록에 있다.
/// 같은 그림을 여러 번 배치한 경우 그림 데이터와 배치 블록의 개수는 다를 수 있다.
nonisolated public struct DocumentEmbeddedImage: Sendable, Equatable {
  /// 문서 내부의 그림 식별자. 형식에 따라 파트 경로나 BinData 이름으로 생성한다.
  public var id: String
  /// 추출한 래스터의 PNG 바이트. 원본 파일의 압축 스트림과 같다고 가정하지 않는다.
  public var pngData: Data
  /// 그림의 원본 앵커. 실제 페이지 좌표를 알 수 없으면 part·문단·셀 위치만 있을 수 있다.
  public var location: DocumentLocation
  /// 원본 문서가 제공한 그림 설명. OCR로 만든 텍스트가 아니다.
  public var sourceDescription: String?
  /// 저장된 PNG를 해석할 때 적용할 이미지 방향.
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
