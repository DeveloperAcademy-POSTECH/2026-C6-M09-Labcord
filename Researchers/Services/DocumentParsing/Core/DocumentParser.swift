import CoreGraphics
import Foundation
import ImageIO

nonisolated public enum DocumentParser {
  public typealias ProgressHandler = @Sendable (DocumentProgress) -> Void

  @concurrent public static func parse(
    _ input: DocumentInput,
    options: DocumentParserOptions = DocumentParserOptions(),
    progress: ProgressHandler? = nil
  ) async throws -> DocumentParseResult {
    try await DocumentOCR.$sessions.withValue(DocumentOCRSessionPool()) {
      try await parseInput(input, index: 0, options: options, progress: progress)
    }
  }

  @concurrent public static func parseBatch(
    _ inputs: [DocumentInput],
    options: DocumentParserOptions = DocumentParserOptions(),
    progress: ProgressHandler? = nil
  ) async throws -> [DocumentBatchResult] {
    try Task.checkCancellation()
    if inputs.isEmpty { return [] }
    let pool = DocumentPDFWorkPool(options: options)
    return try await DocumentOCR.$sessions.withValue(DocumentOCRSessionPool()) {
      try await DocumentPDFScheduling.$pool.withValue(pool) {
        let results = try await runBatch(inputs, options: options, progress: progress)
        let metrics = await pool.snapshot()
        return results.map { outcome in
          guard case .success(var result) = outcome else { return outcome }
          result.metrics?.batchScheduling = metrics
          return .success(result)
        }
      }
    }
  }

  private static func runBatch(
    _ inputs: [DocumentInput], options: DocumentParserOptions, progress: ProgressHandler?
  ) async throws -> [DocumentBatchResult] {
    var results = [DocumentBatchResult?](repeating: nil, count: inputs.count)
    var nextIndex = 0
    try await withThrowingTaskGroup(of: (Int, DocumentBatchResult).self) { group in
      for _ in 0..<min(max(1, options.maximumConcurrentDocuments), inputs.count) {
        let index = nextIndex
        nextIndex += 1
        group.addTask { [options] in
          await parseBatchItem(inputs[index], index: index, options: options, progress: progress)
        }
      }
      while let (index, result) = try await group.next() {
        results[index] = result
        try Task.checkCancellation()
        guard nextIndex < inputs.count else { continue }
        let next = nextIndex
        nextIndex += 1
        group.addTask { [options] in
          await parseBatchItem(inputs[next], index: next, options: options, progress: progress)
        }
      }
    }
    return results.compactMap { $0 }
  }

  private static func parseBatchItem(
    _ input: DocumentInput,
    index: Int,
    options: DocumentParserOptions,
    progress: ProgressHandler?
  ) async -> (Int, DocumentBatchResult) {
    do {
      let result = try await parseInput(input, index: index, options: options, progress: progress)
      return (index, .success(result))
    } catch is CancellationError {
      return (index, .failure(.cancelled))
    } catch let error as DocumentParsingError {
      return (index, .failure(error))
    } catch {
      return (index, .failure(.malformedDocument))
    }
  }

  private static func parseInput(
    _ input: DocumentInput,
    index: Int,
    options: DocumentParserOptions,
    progress: ProgressHandler?
  ) async throws -> DocumentParseResult {
    do {
      return try await parseDocument(input, index: index, options: options, progress: progress)
    } catch {
      let cancelled = error is CancellationError || (error as? DocumentParsingError) == .cancelled
      progress?(
        DocumentProgress(
          inputIndex: index,
          phase: cancelled ? .cancelled : .failed,
          fractionCompleted: 1
        ))
      if cancelled { throw DocumentParsingError.cancelled }
      throw error
    }
  }

  private static func parseDocument(
    _ input: DocumentInput,
    index: Int,
    options: DocumentParserOptions,
    progress: ProgressHandler?
  ) async throws -> DocumentParseResult {
    try Task.checkCancellation()
    var accessedURL: URL?
    var didStartAccess = false
    if case .url(let url) = input {
      guard url.isFileURL else { throw DocumentParsingError.unsupportedFormat }
      didStartAccess = url.startAccessingSecurityScopedResource()
      accessedURL = url
    }
    defer {
      if didStartAccess { accessedURL?.stopAccessingSecurityScopedResource() }
    }

    progress?(DocumentProgress(inputIndex: index, phase: .identifying, fractionCompleted: 0))
    let prepared = try read(input, options: options)
    try Task.checkCancellation()
    let format = try detectFormat(
      data: prepared.data,
      fileName: prepared.fileName,
      isImage: prepared.image != nil,
      options: options)
    progress?(DocumentProgress(inputIndex: index, phase: .extracting, fractionCompleted: 0.1))
    try Task.checkCancellation()
    let result = try await parse(prepared: prepared, format: format, options: options) { event in
      progress?(
        DocumentProgress(
          inputIndex: index,
          phase: event.phase,
          fractionCompleted: 0.1 + event.fractionCompleted * 0.8
        ))
    }
    try Task.checkCancellation()
    progress?(DocumentProgress(inputIndex: index, phase: .completed, fractionCompleted: 1))
    return result
  }

  private struct PreparedInput {
    var data: Data
    var fileName: String?
    var baseDirectory: URL?
    var image: (CGImage, CGImagePropertyOrientation)?
  }

  private static func read(_ input: DocumentInput, options: DocumentParserOptions) throws
    -> PreparedInput {
    switch input {
    case .data(let data, let fileName):
      guard data.count <= options.maximumInputBytes else {
        throw DocumentParsingError.inputTooLarge
      }
      return PreparedInput(data: Data(data), fileName: fileName, baseDirectory: nil, image: nil)
    case .image(let image, let orientation):
      guard image.width > 0, image.height > 0,
        image.width <= options.maximumImagePixels / image.height
      else {
        throw DocumentParsingError.inputTooLarge
      }
      return PreparedInput(
        data: Data(), fileName: nil, baseDirectory: nil, image: (image, orientation))
    case .url(let url):
      do {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size >= 0 else {
          throw DocumentParsingError.unreadableInput
        }
        guard size <= options.maximumInputBytes else { throw DocumentParsingError.inputTooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= options.maximumInputBytes else {
          throw DocumentParsingError.inputTooLarge
        }
        return PreparedInput(
          data: data,
          fileName: url.lastPathComponent,
          baseDirectory: url.deletingLastPathComponent(),
          image: nil
        )
      } catch let error as DocumentParsingError {
        throw error
      } catch {
        throw DocumentParsingError.unreadableInput
      }
    }
  }

  private static func detectFormat(
    data: Data,
    fileName: String?,
    isImage: Bool,
    options: DocumentParserOptions
  ) throws -> DocumentFormat {
    if isImage { return .image }
    return try DocumentFormatDetector.detect(data: data, fileName: fileName, options: options)
  }

  private static func parse(
    prepared: PreparedInput,
    format: DocumentFormat,
    options: DocumentParserOptions,
    progress: ProgressHandler?
  ) async throws -> DocumentParseResult {
    if let (image, orientation) = prepared.image {
      progress?(DocumentProgress(inputIndex: 0, phase: .recognizingText, fractionCompleted: 0.25))
      let blocks = try DocumentOCR.recognize(image: image, orientation: orientation)
      return DocumentParseResult(format: .image, blocks: blocks, warnings: [])
    }
    return try await parse(
      data: prepared.data,
      format: format,
      options: options,
      baseDirectory: prepared.baseDirectory,
      progress: progress
    )
  }

  private static func parse(
    data: Data,
    format: DocumentFormat,
    options: DocumentParserOptions,
    baseDirectory: URL?,
    progress: ProgressHandler?
  ) async throws -> DocumentParseResult {
    switch format {
    case .jpeg, .png, .heic, .tiff:
      return try DocumentRasterParser.parse(
        data, format: format, options: options, progress: progress)
    case .txt, .csv, .json, .xml, .rtf, .html, .markdown:
      return try await DocumentTextParser.parse(
        data,
        format: format,
        baseDirectory: baseDirectory,
        options: options
      )
    case .pdf:
      return try await DocumentPDFParser.parse(data, options: options, progress: progress)
    case .docx, .xlsx, .pptx, .doc, .xls, .ppt:
      return try DocumentOfficeParser.parse(data: data, format: format, options: options)
    case .hwp, .hwpx:
      return try DocumentHWPParser.parse(data: data, format: format, options: options)
    case .image:
      throw DocumentParsingError.unsupportedFormat
    }
  }

}
