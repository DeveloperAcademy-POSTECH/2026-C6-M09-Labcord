import Foundation
import PDFKit

/// PDF 열기·페이지 파이프라인·최종 결과 조합을 담당한다.
/// 페이지 작업 완료 순서와 관계없이 페이지·좌표 순으로 블록을 정리한다.
nonisolated enum DocumentPDFParser {
  static func parse(
    _ data: Data,
    options: DocumentParserOptions,
    progress: DocumentParser.ProgressHandler?
  ) async throws -> DocumentParseResult {
    var timing = DocumentTiming()
    let document = try timing.measure(.pdfOpen) {
      guard let document = PDFDocument(data: data) else {
        throw DocumentParsingError.malformedDocument
      }
      guard !document.isLocked else { throw DocumentParsingError.encryptedDocument }
      guard document.pageCount > 0 else { throw DocumentParsingError.malformedDocument }
      return document
    }
    let count = min(document.pageCount, max(1, options.maximumDocumentPages))
    var pipeline = DocumentPDFPipeline(document: document, options: options, origin: timing.origin)
    let pages = try await pipeline.run(count: count, progress: progress)
    try Task.checkCancellation()
    let start = ContinuousClock.now
    var blocks = pages.flatMap { $0.result.blocks }
    let images = pages.flatMap { $0.result.images }
    var warnings = pages.flatMap { $0.result.warnings }
    if count < document.pageCount {
      warnings.append(DocumentWarning(
        code: .resourceLimitReached, message: "Remaining PDF pages exceeded the configured limit.",
        location: DocumentLocation(page: count + 1)))
    }
    blocks.sort {
      if $0.location.page != $1.location.page {
        return ($0.location.page ?? 0) < ($1.location.page ?? 0)
      }
      let left = $0.location.bounds ?? .zero
      let right = $1.location.bounds ?? .zero
      if left.minY != right.minY { return left.minY < right.minY }
      return left.minX < right.minX
    }
    for index in blocks.indices { blocks[index].readingOrder = index }
    var result = DocumentParseResult(
      format: .pdf, blocks: blocks, warnings: warnings, images: images)
    timing.record(.pdfAssembly, start: start)
    result.metrics = DocumentParsingMetrics(
      wallSeconds: DocumentTiming.seconds(timing.origin.duration(to: .now)),
      peakInFlightPages: pipeline.peakPages, peakEstimatedWorkingBytes: pipeline.peakBytes,
      timings: (timing.values + pages.flatMap { $0.timing.values } + pipeline.awaitTimings.values)
        .sorted { $0.startOffsetSeconds < $1.startOffsetSeconds })
    return result
  }
}
