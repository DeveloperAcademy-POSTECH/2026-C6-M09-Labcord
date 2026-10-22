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
    limits: (images: Int, bytes: Int)
  ) throws -> DocumentPDFPreparedPage {
    guard let reference = page.pageRef else { throw DocumentParsingError.malformedDocument }
    let space = DocumentPDFPageSpace(page: reference)
    guard space.size.width.isFinite, space.size.height.isFinite,
      space.size.width > 0, space.size.height > 0
    else { throw DocumentParsingError.malformedDocument }
    let scanner = DocumentPDFScanner(options: options)
    scanner.scan(reference)
    try Task.checkCancellation()
    let tables = try tables(page, index: index, scanner: scanner, space: space)
    let tableBounds = tables.blocks.filter { $0.kind == .table }.compactMap(\.location.bounds)
    let native = nativeLines(page, index: index, space: space).filter { block in
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
    guard options.extractImages || options.performOCR else {
      return DocumentPDFPreparedPage(index: index, result: result)
    }
    let raster = space.render(page, maximumPixels: options.maximumImagePixels)
    guard let raster else {
      result.warnings.append(
        DocumentWarning(
          code: .resourceLimitReached, message: "PDF page exceeded the rasterization limit.",
          location: DocumentLocation(page: index + 1)))
      return DocumentPDFPreparedPage(index: index, result: result)
    }
    let extracted = try DocumentPDFImageExtractor.prepare(
      scanner: scanner, raster: raster, space: space, pageIndex: index,
      limits: limits)
    result.images = extracted.result.images
    result.inspectedImages = extracted.result.inspectedImages
    result.warnings.append(contentsOf: extracted.result.warnings)
    if !options.performOCR { result.blocks.append(contentsOf: extracted.result.blocks) }
    return DocumentPDFPreparedPage(
      index: index, result: result,
      raster: options.performOCR ? DocumentPDFRaster(image: raster) : nil,
      imageJobs: extracted.jobs, extractImages: options.extractImages,
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
        if page.extractImages {
          page.result.blocks.append(DocumentBlock(
            kind: .image, text: "", readingOrder: 0, location: job.location))
        }
        do {
          let recognized = try DocumentPDFImageExtractor.recognize(
            job.raster.image, location: job.location, bounds: job.location.bounds ?? .zero)
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
      if let raster = page.raster, !recognizedFullPage {
        try appendPageOCR(raster.image, index: page.index, result: &page.result)
      }
      page.raster = nil
      page.imageJobs = []
      return page
    }
  }

  private static func tables(
    _ page: PDFPage, index: Int, scanner: DocumentPDFScanner,
    space: DocumentPDFPageSpace
  ) throws -> DocumentPDFTableExtractor.Result {
    var tables = try DocumentPDFTableExtractor.extract(
      segments: scanner.segments, page: page, pageIndex: index, space: space)
    if tables.blocks.isEmpty {
      let aligned = try DocumentPDFAlignedTableExtractor.extract(
        page: page, pageIndex: index, space: space)
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
    let value = normalized(candidate.text)
    guard !value.isEmpty else { return true }
    var relatedText = ""
    for block in blocks {
      guard !block.text.isEmpty, let other = block.location.bounds,
        other.insetBy(dx: -0.005, dy: -0.005).intersects(bounds)
      else { continue }
      if normalized(block.text) == value { return true }
      relatedText += block.text
    }
    // 페이지 OCR 한 줄이 본문 여러 블록에 걸친 경우도 비교하되, 중간 블록 배열은 만들지 않는다.
    return normalized(relatedText).contains(value)
  }

  private static func normalized(_ text: String) -> String {
    text.lowercased().filter { !$0.isWhitespace }
  }
}
