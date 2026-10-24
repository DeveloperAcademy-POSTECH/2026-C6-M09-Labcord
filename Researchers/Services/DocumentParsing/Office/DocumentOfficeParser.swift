import Foundation
import OdrCore

/// Office 백엔드를 호출한 뒤 앱의 공통 결과 모델로 변환한다.
/// 경로 입력이 필요한 백엔드 때문에 임시 파일을 사용하며 함수 종료 시 디렉터리를 지운다.
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
    if format == .doc || format == .ppt {
      let blocks = try DocumentOfficeOxide.parse(data, format: format)
      let warnings = blocks.first { format == .ppt && $0.kind == .table }.map {
        [DocumentWarning(code: .uncertainReadingOrder,
          message: "PPT table inline order is approximate.", location: $0.location)]
      } ?? []
      return try DocumentLegacyOfficeSupplement.extract(
        data: data, format: format,
        base: DocumentParseResult(format: format, blocks: blocks, warnings: warnings),
        options: options, inspectedImages: 0)
    }
    let documentFile = try decoded.asDocumentFile()
    let document = try documentFile.document()
    let root = try document.rootElement()

    var context = DocumentOfficeParseContext(options: options)
    try context.visit(root, part: nil)
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
