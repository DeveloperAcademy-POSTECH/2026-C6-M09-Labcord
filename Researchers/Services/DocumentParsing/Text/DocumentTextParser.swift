import Foundation

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
