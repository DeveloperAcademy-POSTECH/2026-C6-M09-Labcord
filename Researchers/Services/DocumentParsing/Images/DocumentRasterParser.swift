import Foundation
import ImageIO

/// JPEG·PNG·HEIC·TIFF를 프레임 순서대로 OCR한다.
/// 한 프레임이 실패해도 다른 프레임의 결과를 보존하고, 전부 실패했을 때만 오류를 던진다.
nonisolated enum DocumentRasterParser {
  static func parse(
    _ data: Data,
    format: DocumentFormat,
    options: DocumentParserOptions,
    progress: DocumentParser.ProgressHandler?
  ) throws -> DocumentParseResult {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) > 0
    else { throw DocumentParsingError.malformedDocument }
    let count = CGImageSourceGetCount(source)
    let limit = min(count, max(1, options.maximumDocumentPages))
    var blocks: [DocumentBlock] = []
    var warnings: [DocumentWarning] = []
    var firstError: DocumentParsingError?
    var successfulFrames = 0
    for index in 0..<limit {
      try Task.checkCancellation()
      let location = DocumentLocation(page: format == .tiff ? index + 1 : nil)
      do {
        let recognized = try recognize(source, index: index, options: options, location: location)
        successfulFrames += 1
        for var block in recognized {
          block.readingOrder = blocks.count
          blocks.append(block)
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        let failure = error as? DocumentParsingError ?? .malformedDocument
        firstError = firstError ?? failure
        warnings.append(
          DocumentWarning(
            code: failure == .inputTooLarge ? .resourceLimitReached : .imageOCRFailed,
            message: "Image frame could not be decoded or recognized.",
            location: location
          ))
      }
      progress?(
        DocumentProgress(
          inputIndex: 0, phase: .recognizingText,
          fractionCompleted: Double(index + 1) / Double(limit)
        ))
    }
    if count > limit {
      warnings.append(
        DocumentWarning(
          code: .resourceLimitReached,
          message: "Remaining image frames exceeded the configured page limit.",
          location: DocumentLocation(page: limit + 1)
        ))
    }
    guard successfulFrames > 0 else { throw firstError ?? .malformedDocument }
    return DocumentParseResult(format: format, blocks: blocks, warnings: warnings)
  }

  /// 프레임 하나의 디코딩·OCR 임시 객체를 정리한 뒤 다음 프레임으로 넘어간다.
  private static func recognize(
    _ source: CGImageSource, index: Int, options: DocumentParserOptions, location: DocumentLocation
  ) throws -> [DocumentBlock] {
    try autoreleasepool {
      let decoded = try DocumentImageDecoder.decode(
        source, index: index, maximumPixels: options.maximumImagePixels)
      return try DocumentOCR.recognize(
        image: decoded.image, orientation: decoded.orientation, location: location)
    }
  }

}
