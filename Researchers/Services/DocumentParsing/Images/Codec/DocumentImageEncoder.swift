import CoreGraphics
import Foundation
import ImageIO

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
