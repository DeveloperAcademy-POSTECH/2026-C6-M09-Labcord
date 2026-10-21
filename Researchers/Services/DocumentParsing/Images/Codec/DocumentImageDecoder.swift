import CoreGraphics
import Foundation
import ImageIO

nonisolated enum DocumentImageDecoder {
  static func decode(_ data: Data, maximumPixels: Int) throws -> (
    image: CGImage, orientation: CGImagePropertyOrientation
  ) {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      throw DocumentParsingError.malformedDocument
    }
    return try decode(source, index: 0, maximumPixels: maximumPixels)
  }

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
