import CoreGraphics
import Foundation
import ImageIO

/// PDF에 실제 표시된 그림 영역을 페이지 래스터에서 잘라 PNG와 OCR 작업으로 만든다.
/// 원본 JPEG·필터 스트림의 직접 추출이 아니라 표시 영역의 래스터화 결과를 반환한다.
nonisolated enum DocumentPDFImageExtractor {
  struct Result: Sendable {
    var blocks: [DocumentBlock] = []
    var images: [DocumentEmbeddedImage] = []
    var warnings: [DocumentWarning] = []
    var inspectedImages = 0
  }

  static func prepare(
    scanner: DocumentPDFScanner, raster: CGImage,
    space: DocumentPDFPageSpace, pageIndex: Int, limits: (images: Int, bytes: Int)
  ) throws -> (result: Result, jobs: [DocumentPDFImageJob]) {
    let options = scanner.options
    var result = Result()
    var jobs: [DocumentPDFImageJob] = []
    var bytes = 0
    for placement in scanner.images {
      try Task.checkCancellation()
      let bounds = space.normalized(placement.bounds)
      guard !bounds.isNull, !bounds.isEmpty else { continue }
      let location = DocumentLocation(part: placement.name, page: pageIndex + 1, bounds: bounds)
      guard result.inspectedImages < limits.images else {
        result.warnings.append(
          DocumentWarning(
            code: .resourceLimitReached, message: "PDF image count exceeded the configured limit.",
            location: location))
        break
      }
      result.inspectedImages += 1
      guard let crop = DocumentPDFPageSpace.crop(bounds, from: raster)
      else {
        result.warnings.append(
          DocumentWarning(
            code: .extractionFailed, message: "PDF image region could not be rasterized.",
            location: location))
        continue
      }
      if options.extractImages {
        guard let png = DocumentPDFPNGEncoder.png(crop), png.count <= limits.bytes - bytes else {
          result.warnings.append(DocumentWarning(
            code: .resourceLimitReached, message: "PDF image bytes exceeded the configured limit.",
            location: location))
          continue
        }
        bytes += png.count
        let id = "page[\(pageIndex + 1)]/\(placement.name)"
        result.images.append(DocumentEmbeddedImage(id: id, pngData: png, location: location))
        result.blocks.append(
          DocumentBlock(kind: .image, text: "", readingOrder: 0, location: location))
      }
      if options.performOCR {
        jobs.append(DocumentPDFImageJob(
          raster: DocumentPDFRaster(image: crop), location: location))
      }
    }
    return (result, jobs)
  }

  /// 잘라낸 그림 안의 OCR 좌표를 그림의 페이지 위치·크기에 맞춰 다시 변환한다.
  static func recognize(
    _ crop: CGImage, location: DocumentLocation, bounds: CGRect
  ) throws -> [DocumentBlock] {
    try DocumentOCR.recognize(image: crop, orientation: .up, location: location).map { block in
      var located = block
      if let local = block.location.bounds {
        located.location.bounds = CGRect(
          x: bounds.minX + local.minX * bounds.width,
          y: bounds.minY + local.minY * bounds.height,
          width: local.width * bounds.width, height: local.height * bounds.height)
      }
      return located
    }
  }

}
