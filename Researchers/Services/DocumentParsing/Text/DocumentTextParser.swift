import Foundation

/// 텍스트 디코딩과 형식별 블록 추출을 연결한다.
/// HTML·Markdown의 참조 그림 OCR은 본문 뒤에 붙이므로 인라인 순서 차이를 경고로 남긴다.
nonisolated enum DocumentTextParser {
  static func parse(
    _ data: Data,
    format: DocumentFormat,
    baseDirectory: URL?,
    options: DocumentParserOptions
  ) async throws -> DocumentParseResult {
    try Task.checkCancellation()
    guard let text = DocumentFormatDetector.decodeText(data) else {
      throw DocumentParsingError.malformedDocument
    }
    let blocks: [DocumentBlock] = switch format {
    case .csv:
      DocumentCSVParser.parseCSV(text)
    case .json:
      DocumentStructuredTextParser.parseJSON(text)
    case .xml:
      DocumentStructuredTextParser.parseXML(data, fallbackText: text)
    case .html:
      try DocumentHTMLParser.parseHTML(text)
    case .markdown:
      DocumentMarkdownParser.parseMarkdown(text)
    case .rtf:
      DocumentStructuredTextParser.parseRTF(data, fallbackText: text)
    default:
      DocumentStructuredTextParser.parsePlainText(text)
    }
    var result = DocumentParseResult(format: format, blocks: blocks, warnings: [])
    let warnings = try appendReferencedImages(
      to: &result, text: text, baseDirectory: baseDirectory, options: options)
    return DocumentParseResult(
      format: format, blocks: result.blocks, warnings: warnings, images: result.images)
  }

  /// 그림 하나의 실패는 본문을 버리지 않고 위치 경고로 남긴다. 취소 오류는 계속 전파한다.
  private static func appendReferencedImages(
    to output: inout DocumentParseResult,
    text: String,
    baseDirectory: URL?,
    options: DocumentParserOptions
  ) throws -> [DocumentWarning] {
    guard options.extractImages || options.performOCR,
      output.format == .html || output.format == .markdown
    else { return [] }
    let references = DocumentReferencedImageParser.references(in: text, format: output.format)
    guard !references.isEmpty else { return [] }
    var warnings = [
      DocumentWarning(
        code: .uncertainReadingOrder,
        message: "Referenced image OCR blocks follow text blocks; inline order may differ."
      )
    ]
    var imageBytes = 0
    for (index, reference) in references.enumerated() {
      try Task.checkCancellation()
      // 실패한 참조도 시도로 계산해 손상 그림이 반복돼도 작업량이 무한히 늘지 않게 한다.
      guard index < options.maximumEmbeddedImages else {
        warnings.append(DocumentWarning(
          code: .resourceLimitReached, message: "Referenced image count exceeded the limit.",
          location: DocumentLocation(part: reference)))
        break
      }
      do {
        guard
          let result = try DocumentReferencedImageParser.parse(
            reference, baseDirectory: baseDirectory, options: options,
            remainingBytes: max(0, options.maximumExpandedBytes - imageBytes)
          )
        else {
          warnings.append(DocumentWarning(
            code: .externalImageSkipped,
            message: "External or inaccessible image reference was skipped.",
            location: DocumentLocation(part: reference)))
          continue
        }
        output.images.append(contentsOf: result.images)
        output.blocks.appendInReadingOrder(result.blocks)
        imageBytes += result.images.reduce(0) { $0 + $1.pngData.count }
        warnings.append(contentsOf: result.warnings)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        warnings.append(
          DocumentWarning(
            code: (error as? DocumentParsingError) == .inputTooLarge
              ? .resourceLimitReached : (options.performOCR ? .imageOCRFailed : .extractionFailed),
            message: "Referenced image could not be read or recognized.",
            location: DocumentLocation(part: reference)
          ))
      }
    }
    return warnings
  }

}
