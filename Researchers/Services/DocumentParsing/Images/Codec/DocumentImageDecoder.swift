import CoreGraphics
import Foundation
import ImageIO

/// ImageIO 메타데이터로 픽셀 수를 먼저 확인한 뒤 비트맵을 만든다.
/// EXIF 방향은 픽셀에 직접 적용하지 않고 Vision에 전달할 값으로 함께 반환한다.
nonisolated enum DocumentImageDecoder {
  static func decode(_ data: Data, maximumPixels: Int) throws -> (
    image: CGImage, orientation: CGImagePropertyOrientation
  ) {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      throw DocumentParsingError.malformedDocument
    }
    return try decode(source, index: 0, maximumPixels: maximumPixels)
  }

  /// 프레임별 크기와 방향을 읽는다. 픽셀 수 비교는 곱셈 대신 나눗셈으로 오버플로를 피한다.
  static func decode(_ source: CGImageSource, index: Int, maximumPixels: Int) throws -> (
    image: CGImage, orientation: CGImagePropertyOrientation
  ) {
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else {
      throw DocumentParsingError.malformedDocument
    }
    guard width > 0, height > 0, width <= maximumPixels / height else {
      throw DocumentParsingError.inputTooLarge
    }
    let rawOrientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
    let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
    guard
      let image = CGImageSourceCreateImageAtIndex(
        source, index, [kCGImageSourceShouldCache: false] as CFDictionary)
    else {
      throw DocumentParsingError.malformedDocument
    }
    return (image, orientation)
  }
}
