import Foundation
import ImageIO

/// JPEG·PNG·HEIC·TIFF를 프레임 순서대로 읽고 요청한 PNG 추출·OCR을 수행한다.
/// 한 프레임이 실패해도 다른 프레임의 결과를 보존하고, 전부 실패했을 때만 오류를 던진다.
nonisolated enum DocumentRasterParser {
  static func parse(
    _ data: Data,
    format: DocumentFormat,
    options: DocumentParserOptions,
    progress: DocumentParser.ProgressHandler?
  ) throws -> DocumentParseResult {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) > 0 else { throw DocumentParsingError.malformedDocument }
    guard options.extractImages || options.performOCR else {
      return DocumentParseResult(format: format, blocks: [], warnings: [])
    }
    let count = CGImageSourceGetCount(source)
    let limit = min(count, max(1, options.maximumDocumentPages))
    var blocks: [DocumentBlock] = []
    var warnings: [DocumentWarning] = []
    var images: [DocumentEmbeddedImage] = []
    var imageBytes = 0
    var firstError: DocumentParsingError?
    var successfulFrames = 0
    for index in 0..<limit {
      try Task.checkCancellation()
      let location = DocumentLocation(page: format == .tiff ? index + 1 : nil)
      do {
        let frame = try parseFrame(
          source, index: index, format: format, options: options,
          remainingBytes: max(0, options.maximumExpandedBytes - imageBytes))
        successfulFrames += 1
        images.append(contentsOf: frame.images)
        imageBytes += frame.images.reduce(0) { $0 + $1.pngData.count }
        warnings.append(contentsOf: frame.warnings)
        blocks.appendInReadingOrder(frame.blocks)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        let failure = error as? DocumentParsingError ?? .malformedDocument
        firstError = firstError ?? failure
        warnings.append(DocumentWarning(
          code: failure == .inputTooLarge ? .resourceLimitReached
            : (options.performOCR ? .imageOCRFailed : .extractionFailed),
          message: "Image frame could not be decoded or recognized.", location: location))
      }
      progress?(DocumentProgress(
        inputIndex: 0, phase: options.performOCR ? .recognizingText : .extracting,
        fractionCompleted: Double(index + 1) / Double(limit)))
    }
    if count > limit {
      warnings.append(DocumentWarning(
        code: .resourceLimitReached,
        message: "Remaining image frames exceeded the configured page limit.",
        location: DocumentLocation(page: limit + 1)))
    }
    guard successfulFrames > 0 else { throw firstError ?? .malformedDocument }
    return DocumentParseResult(format: format, blocks: blocks, warnings: warnings, images: images)
  }

  private static func parseFrame(
    _ source: CGImageSource, index: Int, format: DocumentFormat,
    options: DocumentParserOptions, remainingBytes: Int
  ) throws -> DocumentParseResult {
    try autoreleasepool {
      let decoded = try DocumentImageDecoder.decode(
        source, index: index, maximumPixels: options.maximumImagePixels)
      return try parseImage(
        decoded.image, orientation: decoded.orientation, format: format,
        location: DocumentLocation(page: format == .tiff ? index + 1 : nil),
        options: options, remainingBytes: remainingBytes)
    }
  }

  /// 직접 입력·이미지 프레임·로컬 참조 그림이 같은 추출/OCR 설정을 사용한다.
  static func parseImage(
    _ image: CGImage, orientation: CGImagePropertyOrientation, format: DocumentFormat,
    location: DocumentLocation, options: DocumentParserOptions, remainingBytes: Int? = nil
  ) throws -> DocumentParseResult {
    try Task.checkCancellation()
    var blocks: [DocumentBlock] = []
    var images: [DocumentEmbeddedImage] = []
    var warnings: [DocumentWarning] = []
    if options.extractImages {
      if let png = DocumentImageEncoder.png(image, orientation: orientation),
        png.count <= (remainingBytes ?? options.maximumExpandedBytes) {
        images.append(DocumentEmbeddedImage(
          id: location.part ?? "\(format.rawValue)/frame[\(location.page ?? 1)]",
          pngData: png, location: location, orientation: orientation))
        blocks.append(DocumentBlock(kind: .image, text: "", readingOrder: 0, location: location))
      } else {
        warnings.append(DocumentWarning(
          code: .resourceLimitReached, message: "Image raster could not be retained.",
          location: location))
      }
    }
    if options.performOCR {
      do {
        blocks.append(contentsOf: try DocumentOCR.recognize(
          image: image, orientation: orientation, location: location))
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        // PNG를 이미 추출했다면 OCR 실패로 해당 그림까지 버리지 않는다.
        guard !images.isEmpty else { throw error }
        warnings.append(DocumentWarning(
          code: .imageOCRFailed, message: "Image OCR failed; the raster is preserved.",
          location: location))
      }
    }
    return DocumentParseResult(format: format, blocks: blocks, warnings: warnings, images: images)
  }
}
