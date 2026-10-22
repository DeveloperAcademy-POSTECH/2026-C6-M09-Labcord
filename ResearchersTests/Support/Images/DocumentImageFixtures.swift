import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UIKit

/// 시스템 글꼴로 OCR 그림과 PDF·TIFF를 만든다. 글꼴 파일이나 외부 문서를 테스트 자산으로 복제하지 않는다.
nonisolated enum DocumentImageFixtures {
  static func textImage(_ text: String) -> CGImage? {
    let width = 1200
    let height = 240
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    context.setFillColor(UIColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateWithName("Helvetica" as CFString, 100, nil)
    let attributed = NSAttributedString(
      string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
    let line = CTLineCreateWithAttributedString(attributed)
    context.setFillColor(UIColor.black.cgColor)
    context.textPosition = CGPoint(x: 80, y: 80)
    CTLineDraw(line, context)
    return context.makeImage()
  }

  static func pdf(draw: (UIGraphicsPDFRendererContext) -> Void) -> Data {
    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
    return renderer.pdfData { context in
      context.beginPage()
      draw(context)
    }
  }

  static func multiPagePDF() -> Data {
    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
    return renderer.pdfData { context in
      context.beginPage()
      ("Page One Marker" as NSString).draw(
        at: CGPoint(x: 40, y: 700),
        withAttributes: [.font: UIFont.systemFont(ofSize: 28)]
      )
      context.beginPage()
      ("Page Two Marker" as NSString).draw(
        at: CGPoint(x: 40, y: 40),
        withAttributes: [.font: UIFont.systemFont(ofSize: 28)]
      )
    }
  }

  static func tiff(_ frames: [(CGImage, CGImagePropertyOrientation)]) throws -> Data {
    let data = NSMutableData()
    guard let target = CGImageDestinationCreateWithData(
      data, "public.tiff" as CFString, frames.count, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    for (image, orientation) in frames {
      CGImageDestinationAddImage(target, image, [
        kCGImagePropertyOrientation: orientation.rawValue
      ] as CFDictionary)
    }
    guard CGImageDestinationFinalize(target) else { throw CocoaError(.fileWriteUnknown) }
    return data as Data
  }

}
