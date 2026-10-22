import CoreGraphics
import Foundation
import ImageIO

/// 추출한 비트맵을 방향 메타데이터가 포함된 PNG로 보관한다.
/// 원본 압축 스트림을 그대로 돌려주는 기능은 아니다.
nonisolated enum DocumentImageEncoder {
  static func png(
    _ image: CGImage, orientation: CGImagePropertyOrientation = .up
  ) -> Data? {
    let data = NSMutableData()
    guard let target = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(target, image, [
      kCGImagePropertyOrientation: orientation.rawValue
    ] as CFDictionary)
    guard CGImageDestinationFinalize(target) else { return nil }
    return data as Data
  }
}
