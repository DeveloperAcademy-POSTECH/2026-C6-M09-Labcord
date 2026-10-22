import CoreGraphics
import Foundation
import ImageIO
import XCTest

@testable import Researchers

/// PNG 용량만 비교하지 않고 디코딩한 픽셀·색 공간을 대조해 팔레트 최적화의 무손실 조건을 확인한다.
final class DocumentPDFPNGEncoderTests: XCTestCase {
  func testPalettePNGPreservesEveryDecodedPixel() throws {
    for colors in [1, 16, 256] {
      let image = try makeImage(colors: colors)
      let old = try XCTUnwrap(DocumentImageEncoder.png(image))
      let optimized = try XCTUnwrap(DocumentPDFPNGEncoder.png(image))
      XCTAssertEqual(try pixels(old), try pixels(optimized))
      XCTAssertLessThan(optimized.count, old.count)
    }
  }

  func testWideGamutPaletteKeepsOriginalColorSpaceAndPixels() throws {
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
    let image = try makeImage(colors: 256, colorSpace: space)
    let old = try XCTUnwrap(DocumentImageEncoder.png(image))
    let optimized = try XCTUnwrap(DocumentPDFPNGEncoder.png(image))
    XCTAssertEqual(old, optimized)
    XCTAssertEqual(try pixels(old, colorSpace: space), try pixels(optimized, colorSpace: space))
  }

  func testManyColorsAndTransparencyUseUnchangedEncoder() throws {
    for (colors, alpha) in [(512, false), (16, true)] {
      let image = try makeImage(colors: colors, alpha: alpha)
      XCTAssertEqual(DocumentPDFPNGEncoder.png(image), DocumentImageEncoder.png(image))
    }
  }

  func testRealScannedPagePNGPreservesEveryDecodedPixel() throws {
    let url = try DocumentScanStressSupport.url("usgs-pp158")
    let data = try Data(contentsOf: url)
    let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
    let document = try XCTUnwrap(CGPDFDocument(provider))
    let page = try XCTUnwrap(document.page(at: 26))
    let space = DocumentPDFPageSpace(page: page)
    let image = try XCTUnwrap(CGContext(
      data: nil, width: 1224, height: 1584, bitsPerComponent: 8, bytesPerRow: 1224 * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    image.setFillColor(gray: 1, alpha: 1)
    image.fill(CGRect(x: 0, y: 0, width: 1224, height: 1584))
    image.scaleBy(x: 1224 / space.size.width, y: 1584 / space.size.height)
    image.concatenate(space.transform)
    image.drawPDFPage(page)
    let raster = try XCTUnwrap(image.makeImage())
    let old = try XCTUnwrap(DocumentImageEncoder.png(raster))
    let optimized = try XCTUnwrap(DocumentPDFPNGEncoder.png(raster))
    XCTAssertEqual(try pixels(old), try pixels(optimized))
    XCTAssertLessThan(optimized.count, old.count)
  }

  private func makeImage(
    colors: Int, alpha: Bool = false, colorSpace: CGColorSpace? = nil
  ) throws -> CGImage {
    let width = 512
    let height = 128
    var data = Data(count: width * height * 4)
    data.withUnsafeMutableBytes { storage in
      let values = storage.bindMemory(to: UInt8.self)
      for index in 0..<(width * height) {
        let color = (index / 4) % colors
        values[index * 4] = UInt8(color % 256)
        values[index * 4 + 1] = UInt8(color / 256)
        values[index * 4 + 2] = UInt8(color % 256)
        values[index * 4 + 3] = alpha ? 128 : 255
      }
    }
    return try XCTUnwrap(CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
      provider: CGDataProvider(data: data as CFData)!, decode: nil,
      shouldInterpolate: false, intent: .defaultIntent))
  }

  private func pixels(_ png: Data, colorSpace: CGColorSpace? = nil) throws -> Data {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let context = try XCTUnwrap(CGContext(
      data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
      bytesPerRow: image.width * 4,
      space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
        | CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return Data(bytes: try XCTUnwrap(context.data), count: image.width * image.height * 4)
  }
}
