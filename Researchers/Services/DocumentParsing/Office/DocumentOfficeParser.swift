import Foundation
import OdrCore

nonisolated enum DocumentOfficeParser {
  static func parse(
    data: Data,
    format: DocumentFormat,
    options: DocumentParserOptions
  ) throws -> DocumentParseResult {
    if [.docx, .xlsx, .pptx].contains(format) {
      try DocumentArchiveGuard.validate(data, options: options)
    }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("DocumentParsing-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("input.\(format.rawValue)")
    try data.write(to: fileURL, options: .atomic)

    let decoded = try DecodedFile.decode(path: fileURL.path)
    guard !decoded.isPasswordEncrypted else { throw DocumentParsingError.encryptedDocument }
    let documentFile = try decoded.asDocumentFile()
    let document = try documentFile.document()
    let root = try document.rootElement()

    var context = DocumentOfficeParseContext(options: options, format: format)
    try context.visit(root, part: nil)
    if [.xlsx, .xls].contains(format), context.blocks.isEmpty {
      context.extractSpreadsheetHTML(from: decoded)
    }
    if context.blocks.isEmpty, context.images.isEmpty {
      context.warnings.append(
        DocumentWarning(
          code: .extractionFailed,
          message: "The Office parser returned no readable text, table, or image blocks.",
          location: DocumentLocation(part: format.rawValue)
        ))
    }
    let result = DocumentParseResult(
      format: format, blocks: context.blocks, warnings: context.warnings, images: context.images)
    if [.doc, .xls, .ppt].contains(format) {
      return try DocumentLegacyOfficeSupplement.extract(
        data: data, format: format, base: result, options: options,
        inspectedImages: context.imageAttempts)
    }
    return result
  }

}
