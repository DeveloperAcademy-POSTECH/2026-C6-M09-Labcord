import Foundation
import PDFKit

/// PDFKit 접근과 이미지 예산 할당은 한 작업에서 수행하고, 불변 래스터 OCR만 병렬화한다.
/// 문서 안에서는 다음 페이지를 순서대로 준비하고 끝난 OCR 결과를 인덱스로 보관한다.
/// 그래서 실행 순서가 달라져도 이미지 보존 예산과 반환 페이지 순서는 일정하다.
nonisolated struct DocumentPDFPipeline {
  let document: PDFDocument
  let options: DocumentParserOptions
  let origin: ContinuousClock.Instant
  var imageBytes = 0
  var inspectedImages = 0
  var peakPages = 0
  var peakBytes = 0
  var estimateMultiplier = 1.0
  var awaitTimings = DocumentTiming()

  mutating func run(
    count: Int, progress: DocumentParser.ProgressHandler?
  ) async throws -> [DocumentPDFPreparedPage] {
    let workers = min(count, max(1, options.maximumConcurrentPDFPages),
                      max(1, ProcessInfo.processInfo.activeProcessorCount))
    let memoryTarget = max(1, options.pdfWorkingMemoryTargetBytes)
    var output = [DocumentPDFPreparedPage?](repeating: nil, count: count)
    var inFlight = 0
    var workingBytes = 0
    var next = 0
    var completed = 0
    awaitTimings = DocumentTiming(origin: origin)
    try await withThrowingTaskGroup(of: DocumentPDFPreparedPage.self) { group in
      while next < count || inFlight > 0 {
        try Task.checkCancellation()
        let estimate = next < count ? estimatedBytes(at: next) : 0
        // 상한보다 큰 한 페이지는 해상도를 줄이지 않고 단독으로 처리한다.
        let fits = inFlight == 0 || estimate <= max(0, memoryTarget - workingBytes)
        if next < count, inFlight < workers, fits {
          let pool = DocumentPDFScheduling.pool
          let lease = try await DocumentPDFScheduling.acquire(
            estimatedBytes: estimate, page: next + 1, timing: &awaitTimings)
          let page: DocumentPDFPreparedPage
          do {
            try Task.checkCancellation()
            page = try prepare(index: next)
            if let lease { await pool?.resize(lease, actualBytes: page.estimatedBytes) }
          } catch {
            if let lease { await pool?.release(lease) }
            throw error
          }
          updateEstimate(page, estimatedBytes: estimate)
          workingBytes += page.estimatedBytes
          inFlight += 1
          peakPages = max(peakPages, inFlight)
          peakBytes = max(peakBytes, workingBytes)
          next += 1
          group.addTask { try await DocumentPDFScheduling.recognize(page, lease: lease) }
          continue
        }
        let start = ContinuousClock.now
        guard let page = try await group.next() else { break }
        awaitTimings.record(.pdfAwait, start: start)
        workingBytes -= page.estimatedBytes
        inFlight -= 1
        completed += 1
        output[page.index] = page
        progress?(DocumentProgress(
          inputIndex: 0, phase: .recognizingText,
          fractionCompleted: Double(completed) / Double(count)))
      }
    }
    return output.compactMap { $0 }
  }

  /// 실제 준비한 래스터가 예상보다 크면 다음 페이지의 예약량을 보수적으로 올린다.
  private mutating func updateEstimate(_ page: DocumentPDFPreparedPage, estimatedBytes: Int) {
    let reserve = DocumentPDFWorkingMemory.recognitionReserveBytes
    let unscaled = max(1, Double(max(0, estimatedBytes - reserve)) / estimateMultiplier)
    let rasterBytes = max(0, page.estimatedBytes - reserve)
    estimateMultiplier = max(estimateMultiplier, Double(rasterBytes) / unscaled)
  }

  private var imageBudget: Int {
    min(options.maximumExpandedBytes, options.maximumPDFImageBytes)
  }

  /// 이미지 개수·PNG 바이트를 원본 페이지 순서대로 차감한다. 페이지 실패는 위치 경고로 복구한다.
  private mutating func prepare(index: Int) throws -> DocumentPDFPreparedPage {
    do {
      guard let page = document.page(at: index) else {
        throw DocumentParsingError.malformedDocument
      }
      let prepared = try autoreleasepool {
        try DocumentPDFPageParser.prepare(
          page, index: index, options: options,
          limits: (max(0, options.maximumEmbeddedImages - inspectedImages),
                   max(0, imageBudget - imageBytes)), origin: origin)
      }
      inspectedImages += prepared.result.inspectedImages
      imageBytes += prepared.result.images.reduce(0) { $0 + $1.pngData.count }
      return prepared
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return DocumentPDFPreparedPage(index: index, result: .init(warnings: [DocumentWarning(
        code: .extractionFailed, message: "PDF page could not be extracted.",
        location: DocumentLocation(page: index + 1))]), timing: DocumentTiming(origin: origin))
    }
  }

  private func estimatedBytes(at index: Int) -> Int {
    guard let reference = document.page(at: index)?.pageRef else { return 0 }
    let size = DocumentPDFPageSpace(page: reference).size
    let area = size.width * size.height
    guard area.isFinite, area > 0 else { return 0 }
    let pixels = min(Double(max(1, options.maximumImagePixels)), Double(area) * 4)
    // RGBA/crop/인코딩과 Vision 작업 여유를 예약한다. 프로세스 메모리의 강제 상한은 아니다.
    return Int(min(Double(Int.max / 24), ceil(pixels * estimateMultiplier))) * 12
      + DocumentPDFWorkingMemory.recognitionReserveBytes
  }
}
