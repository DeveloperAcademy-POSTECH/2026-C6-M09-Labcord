import CoreGraphics
import Foundation
import ImageIO

nonisolated enum DocumentPDFImageExtractor {
  struct Result: Sendable {
    var blocks: [DocumentBlock] = []
    var images: [DocumentEmbeddedImage] = []
    var warnings: [DocumentWarning] = []
    var inspectedImages = 0
  }

  static func prepare(
    placements: [DocumentPDFScanner.Placement], raster: CGImage,
    space: DocumentPDFPageSpace, pageIndex: Int, limits: (images: Int, bytes: Int)
  ) throws -> (result: Result, jobs: [DocumentPDFImageJob]) {
    var result = Result()
    var jobs: [DocumentPDFImageJob] = []
    var bytes = 0
    for placement in placements {
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
      guard let crop = DocumentPDFPageSpace.crop(bounds, from: raster),
        let png = DocumentPDFPNGEncoder.png(crop)
      else {
        result.warnings.append(
          DocumentWarning(
            code: .extractionFailed, message: "PDF image region could not be rasterized.",
            location: location))
        continue
      }
      guard png.count <= limits.bytes - bytes else {
        result.warnings.append(
          DocumentWarning(
            code: .resourceLimitReached, message: "PDF image bytes exceeded the configured limit.",
            location: location))
        continue
      }
      bytes += png.count
      let id = "page[\(pageIndex + 1)]/\(placement.name)"
      result.images.append(DocumentEmbeddedImage(id: id, pngData: png, location: location))
      result.blocks.append(
        DocumentBlock(kind: .image, text: "", readingOrder: 0, location: location))
      jobs.append(DocumentPDFImageJob(raster: DocumentPDFRaster(image: crop), location: location))
    }
    return (result, jobs)
  }

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
