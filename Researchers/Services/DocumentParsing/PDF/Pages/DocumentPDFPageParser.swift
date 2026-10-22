import CoreGraphics
import Foundation
import ImageIO
import PDFKit

/// 한 페이지를 직렬 준비 단계와 병렬 OCR 단계로 나눈다.
/// PDFKit 객체는 준비 단계에 남기고 OCR 작업에는 불변 래스터와 위치만 전달한다.
nonisolated enum DocumentPDFPageParser {
  /// 본문·표·그림 위치를 읽고 래스터를 만든다. 표 영역의 본문은 셀 텍스트와 겹치지 않게 제외한다.
  static func prepare(
    _ page: PDFPage, index: Int, options: DocumentParserOptions,
    limits: (images: Int, bytes: Int), origin: ContinuousClock.Instant
  ) throws -> DocumentPDFPreparedPage {
    var timing = DocumentTiming(origin: origin)
    guard let reference = page.pageRef else { throw DocumentParsingError.malformedDocument }
    let space = DocumentPDFPageSpace(page: reference)
    guard space.size.width.isFinite, space.size.height.isFinite,
      space.size.width > 0, space.size.height > 0
    else { throw DocumentParsingError.malformedDocument }
    let scanner = DocumentPDFScanner(options: options)
    timing.measure(.pdfScan, page: index + 1) { scanner.scan(reference) }
    try Task.checkCancellation()
    let tables = try tables(page, index: index, scanner: scanner, space: space, timing: &timing)
    let tableBounds = tables.blocks.filter { $0.kind == .table }.compactMap(\.location.bounds)
    let native = timing.measure(.pdfNativeText, page: index + 1) {
      nativeLines(page, index: index, space: space)
    }.filter { block in
      guard let bounds = block.location.bounds else { return true }
      return !tableBounds.contains { $0.contains(CGPoint(x: bounds.midX, y: bounds.midY)) }
    }
    var result = DocumentPDFImageExtractor.Result(
      blocks: native + tables.blocks, warnings: tables.warnings)
    if scanner.limited || scanner.malformed {
      result.warnings.append(
        DocumentWarning(
          code: scanner.limited ? .resourceLimitReached : .extractionFailed,
          message: "Some PDF drawing operations could not be inspected.",
          location: DocumentLocation(page: index + 1)))
    }
    let raster = timing.measure(.pdfRender, page: index + 1) {
      space.render(page, maximumPixels: options.maximumImagePixels)
    }
    guard let raster else {
      result.warnings.append(
        DocumentWarning(
          code: .resourceLimitReached, message: "PDF page exceeded the rasterization limit.",
          location: DocumentLocation(page: index + 1)))
      return DocumentPDFPreparedPage(index: index, result: result, timing: timing)
    }
    let extracted = try timing.measure(.pdfImages, page: index + 1) {
      try DocumentPDFImageExtractor.prepare(
        placements: scanner.images, raster: raster, space: space, pageIndex: index,
        limits: limits)
    }
    result.images = extracted.result.images
    result.inspectedImages = extracted.result.inspectedImages
    result.warnings.append(contentsOf: extracted.result.warnings)
    return DocumentPDFPreparedPage(
      index: index, result: result, raster: DocumentPDFRaster(image: raster),
      imageJobs: extracted.jobs, timing: timing,
      estimatedBytes: raster.bytesPerRow * raster.height * 3
        + DocumentPDFWorkingMemory.recognitionReserveBytes)
  }

  @concurrent static func recognize(
    _ prepared: DocumentPDFPreparedPage
  ) async throws -> DocumentPDFPreparedPage {
    try await withTaskExecutorPreference(DocumentPDFTaskExecutor.shared) {
      try await performRecognition(prepared)
    }
  }

  /// 그림 OCR이 페이지 전체와 정확히 같은 픽셀 영역을 읽은 경우에만 전체 페이지 OCR을 재사용한다.
  @concurrent private static func performRecognition(
    _ prepared: DocumentPDFPreparedPage
  ) async throws -> DocumentPDFPreparedPage {
    try autoreleasepool {
      var page = prepared
      let native = page.result.blocks
      var recognizedFullPage = false
      for job in page.imageJobs {
        try Task.checkCancellation()
        page.result.blocks.append(DocumentBlock(
          kind: .image, text: "", readingOrder: 0, location: job.location))
        do {
          let recognized = try page.timing.measure(.pdfImageOCR, page: page.index + 1) {
            try DocumentPDFImageExtractor.recognize(
              job.raster.image, location: job.location, bounds: job.location.bounds ?? .zero)
          }
          recognizedFullPage = recognizedFullPage || job.covers(page.raster)
          page.result.blocks.append(contentsOf: recognized.filter { !duplicate($0, in: native) })
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          page.result.warnings.append(DocumentWarning(
            code: .imageOCRFailed, message: "PDF image OCR failed; raster region is preserved.",
            location: job.location))
        }
      }
      if let raster = page.raster {
        let start = ContinuousClock.now
        if recognizedFullPage {
          page.timing.record(.pdfPageOCRReuse, page: page.index + 1, start: start)
        } else {
          try appendPageOCR(raster.image, index: page.index, result: &page.result)
          page.timing.record(.pdfPageOCR, page: page.index + 1, start: start)
        }
      }
      page.raster = nil
      page.imageJobs = []
      return page
    }
  }

  private static func tables(
    _ page: PDFPage, index: Int, scanner: DocumentPDFScanner,
    space: DocumentPDFPageSpace, timing: inout DocumentTiming
  ) throws -> DocumentPDFTableExtractor.Result {
    var tables = try timing.measure(.pdfTables, page: index + 1) {
      try DocumentPDFTableExtractor.extract(
        segments: scanner.segments, page: page, pageIndex: index, space: space)
    }
    if tables.blocks.isEmpty {
      let aligned = try timing.measure(.pdfTables, page: index + 1) {
        try DocumentPDFAlignedTableExtractor.extract(
          page: page, pageIndex: index, space: space)
      }
      tables.blocks = aligned.blocks
      tables.warnings.append(contentsOf: aligned.warnings)
    }
    return tables
  }

  private static func nativeLines(
    _ page: PDFPage, index: Int, space: DocumentPDFPageSpace
  ) -> [DocumentBlock] {
    guard let selection = page.selection(for: space.page.getBoxRect(.mediaBox)) else { return [] }
    return selection.selectionsByLine().compactMap { line in
      let text = (line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }
      return DocumentBlock(
        kind: .paragraph, text: text, readingOrder: 0,
        location: DocumentLocation(
          page: index + 1, bounds: space.normalized(line.bounds(for: page))))
    }
  }

  private static func appendPageOCR(
    _ image: CGImage, index: Int, result: inout DocumentPDFImageExtractor.Result
  ) throws {
    do {
      let recognized = try DocumentOCR.recognize(
        image: image, orientation: .up, location: DocumentLocation(page: index + 1))
      result.blocks.append(contentsOf: recognized.filter { !duplicate($0, in: result.blocks) })
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      result.warnings.append(
        DocumentWarning(
          code: .imageOCRFailed, message: "PDF page OCR could not be completed.",
          location: DocumentLocation(page: index + 1)))
    }
  }

  /// 공간적으로 겹치는 기존 블록만 비교해 같은 문구의 중복 OCR을 제거한다.
  private static func duplicate(_ candidate: DocumentBlock, in blocks: [DocumentBlock]) -> Bool {
    guard candidate.kind == .imageOCR, let bounds = candidate.location.bounds else { return false }
    let related = blocks.filter { block in
      guard !block.text.isEmpty, let other = block.location.bounds else { return false }
      return other.insetBy(dx: -0.005, dy: -0.005).intersects(bounds)
    }
    let value = normalized(candidate.text)
    guard !value.isEmpty else { return true }
    return related.contains { normalized($0.text) == value }
      || normalized(related.map(\.text).joined()).contains(value)
  }

  private static func normalized(_ text: String) -> String {
    text.lowercased().filter { !$0.isWhitespace }
  }
}
