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
    var blocks = try parseBlocks(data, text: text, format: format)
    let warnings = try appendReferencedImages(
      to: &blocks,
      text: text,
      format: format,
      baseDirectory: baseDirectory,
      options: options
    )
    return DocumentParseResult(format: format, blocks: blocks, warnings: warnings)
  }

  private static func parseBlocks(
    _ data: Data,
    text: String,
    format: DocumentFormat
  ) throws -> [DocumentBlock] {
    switch format {
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
  }

  /// 그림 하나의 실패는 본문을 버리지 않고 위치 경고로 남긴다. 취소 오류는 계속 전파한다.
  private static func appendReferencedImages(
    to blocks: inout [DocumentBlock],
    text: String,
    format: DocumentFormat,
    baseDirectory: URL?,
    options: DocumentParserOptions
  ) throws -> [DocumentWarning] {
    guard format == .html || format == .markdown else { return [] }
    let references = DocumentReferencedImageParser.references(in: text, format: format)
    guard !references.isEmpty else { return [] }
    var warnings = [
      DocumentWarning(
        code: .uncertainReadingOrder,
        message: "Referenced image OCR blocks follow text blocks; inline order may differ."
      )
    ]
    for reference in references {
      try Task.checkCancellation()
      do {
        guard
          let imageBlocks = try DocumentReferencedImageParser.recognize(
            reference, baseDirectory: baseDirectory, options: options
          )
        else {
          warnings.append(
            DocumentWarning(
              code: .externalImageSkipped,
              message: "External or inaccessible image reference was skipped.",
              location: DocumentLocation(part: reference)
            ))
          continue
        }
        for var block in imageBlocks {
          block.readingOrder = blocks.count
          blocks.append(block)
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        warnings.append(
          DocumentWarning(
            code: .imageOCRFailed,
            message: "Referenced image could not be read or recognized.",
            location: DocumentLocation(part: reference)
          ))
      }
    }
    return warnings
  }
}
