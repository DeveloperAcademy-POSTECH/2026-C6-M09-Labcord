import CoreGraphics
import Foundation
import ImageIO
import PDFKit

/// PDF 원본 좌표와 앱의 좌상단 정규화 좌표 사이를 변환한다.
/// MediaBox 원점과 페이지 회전을 같은 변환에 반영해 본문·표·그림의 위치를 맞춘다.
nonisolated struct DocumentPDFPageSpace {
  let page: CGPDFPage
  let size: CGSize
  let transform: CGAffineTransform

  init(page: CGPDFPage) {
    self.page = page
    let box = page.getBoxRect(.mediaBox)
    let sideways = abs(page.rotationAngle) % 180 == 90
    size = sideways ? CGSize(width: box.height, height: box.width) : box.size
    transform = page.getDrawingTransform(
      .mediaBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true)
  }

  /// PDF 좌표를 회전 반영 후 0...1 좌표로 바꾸고 페이지 바깥 영역을 잘라낸다.
  func normalized(_ source: CGRect) -> CGRect {
    let rect = source.applying(transform)
    return CGRect(
      x: rect.minX / size.width, y: 1 - rect.maxY / size.height,
      width: rect.width / size.width, height: rect.height / size.height
    )
    .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
  }

  /// 정규화된 표시 영역을 PDFKit 텍스트 선택에 사용할 원본 좌표로 되돌린다.
  func source(_ normalized: CGRect) -> CGRect {
    CGRect(
      x: normalized.minX * size.width, y: (1 - normalized.maxY) * size.height,
      width: normalized.width * size.width, height: normalized.height * size.height
    )
    .applying(transform.inverted())
  }

  /// 기본 2배 크기를 픽셀 한도 안에서 렌더링하고 PDFKit과 수명이 분리된 비트맵 사본을 만든다.
  func render(_ source: PDFPage, maximumPixels: Int) -> CGImage? {
    let area = size.width * size.height
    guard area.isFinite, area > 0, maximumPixels > 0 else { return nil }
    let scale = min(2, sqrt(CGFloat(maximumPixels) / area))
    guard size.width * scale <= CGFloat(maximumPixels),
      size.height * scale <= CGFloat(maximumPixels)
    else { return nil }
    let width = max(1, Int(floor(size.width * scale)))
    let height = max(1, Int(floor(size.height * scale)))
    guard width >= 16, height >= 16, width <= maximumPixels / height,
      let image = source.thumbnail(of: CGSize(width: width, height: height), for: .mediaBox)
        .cgImage,
      image.height > 0, image.width <= maximumPixels / image.height
    else { return nil }
    // PDFKit의 지연 데이터 공급자를 OCR 작업으로 넘기지 않고 픽셀을 소유한 사본을 만든다.
    let colorSpace = image.colorSpace?.model == .rgb ? image.colorSpace
      : CGColorSpace(name: CGColorSpace.sRGB)
    guard let colorSpace,
      let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()
  }

  static func crop(_ bounds: CGRect, from image: CGImage) -> CGImage? {
    let pixels = CGRect(
      x: bounds.minX * CGFloat(image.width),
      y: bounds.minY * CGFloat(image.height),
      width: bounds.width * CGFloat(image.width),
      height: bounds.height * CGFloat(image.height)
    ).integral
    return image.cropping(to: pixels)
  }

}
