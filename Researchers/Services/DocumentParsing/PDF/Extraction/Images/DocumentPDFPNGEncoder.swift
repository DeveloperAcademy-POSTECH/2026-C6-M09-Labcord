import CoreGraphics
import Foundation

/// 256색 이하의 불투명 이미지만 정확한 RGB 팔레트로 바꾼다. 양자화·리사이즈는 하지 않는다.
/// 정확히 표현할 수 있는 팔레트가 없으면 일반 PNG 인코더로 돌아간다.
/// PNG 바이트 크기만 줄이며 OCR에 전달하는 원본 래스터는 바꾸지 않는다.
nonisolated enum DocumentPDFPNGEncoder {
  static func png(_ source: CGImage) -> Data? {
    autoreleasepool {
      if let image = indexed(source), let data = DocumentImageEncoder.png(image) { return data }
      return DocumentImageEncoder.png(source)
    }
  }

  private static func supportsPalette(_ space: CGColorSpace) -> Bool {
    // 광색역 PNG의 팔레트 색 관리에는 반올림 차이가 있어 기존 인코더를 유지한다.
    (space.name as String?) == (CGColorSpace.sRGB as String)
      || CFEqual(space, CGColorSpaceCreateDeviceRGB())
  }

  private static func indexed(_ source: CGImage) -> CGImage? {
    guard source.bitsPerComponent == 8, source.colorSpace?.model == .rgb,
      source.width > 0, source.height > 0,
      source.width <= Int.max / 4 / source.height,
      let space = source.colorSpace, supportsPalette(space),
      let context = CGContext(
        data: nil, width: source.width, height: source.height, bitsPerComponent: 8,
        bytesPerRow: source.width * 4, space: space,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
          | CGImageAlphaInfo.premultipliedLast.rawValue),
      let storage = context.data
    else { return nil }
    context.interpolationQuality = .none
    context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
    let pixels = storage.bindMemory(to: UInt8.self, capacity: source.width * source.height * 4)
    guard let palette = palette(pixels, count: source.width * source.height),
      let colorSpace = CGColorSpace(
        indexedBaseSpace: space, last: palette.colors.count / 3 - 1, colorTable: palette.colors),
      let provider = CGDataProvider(data: palette.indices as CFData)
    else { return nil }
    return CGImage(
      width: source.width, height: source.height, bitsPerComponent: 8, bitsPerPixel: 8,
      bytesPerRow: source.width, space: colorSpace, bitmapInfo: [], provider: provider,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent)
  }

  /// 투명 픽셀이 없고 실제 색이 256개 이하일 때만 색을 그대로 인덱스에 대응시킨다.
  private static func palette(_ pixels: UnsafePointer<UInt8>, count: Int)
    -> (colors: [UInt8], indices: Data)? {
    var colors: [UInt8] = []
    var lookup: [UInt32: UInt8] = [:]
    var indices = Data(count: count)
    let success = indices.withUnsafeMutableBytes { storage -> Bool in
      let output = storage.bindMemory(to: UInt8.self)
      for index in 0..<count {
        let offset = index * 4
        guard pixels[offset + 3] == 255 else { return false }
        let color = UInt32(pixels[offset]) << 16 | UInt32(pixels[offset + 1]) << 8
          | UInt32(pixels[offset + 2])
        if let value = lookup[color] {
          output[index] = value
        } else {
          guard lookup.count < 256 else { return false }
          let value = UInt8(lookup.count)
          lookup[color] = value
          colors.append(contentsOf: [pixels[offset], pixels[offset + 1], pixels[offset + 2]])
          output[index] = value
        }
      }
      return true
    }
    return success ? (colors, indices) : nil
  }
}
