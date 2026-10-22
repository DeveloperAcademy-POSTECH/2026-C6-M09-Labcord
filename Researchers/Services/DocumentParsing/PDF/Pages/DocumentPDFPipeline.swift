import Foundation
import PDFKit

/// 기본 구조 추출은 페이지 순서대로 처리한다. 병렬 작업 예산은 배치 PR에서 연결한다.
nonisolated struct DocumentPDFPipeline {
  let document: PDFDocument
  let options: DocumentParserOptions

  mutating func run(count: Int, progress: DocumentParser.ProgressHandler?) async throws
    -> [DocumentPDFPreparedPage] {
    var output: [DocumentPDFPreparedPage] = []
    var inspectedImages = 0
    var imageBytes = 0
    for index in 0..<count {
      try Task.checkCancellation()
      do {
        guard let page = document.page(at: index) else {
          throw DocumentParsingError.malformedDocument
        }
        let prepared = try autoreleasepool {
          try DocumentPDFPageParser.prepare(page, index: index, options: options,
            limits: (max(0, options.maximumEmbeddedImages - inspectedImages),
                     max(0, min(options.maximumExpandedBytes,
                                options.maximumPDFImageBytes) - imageBytes)))
        }
        inspectedImages += prepared.result.inspectedImages
        imageBytes += prepared.result.images.reduce(0) { $0 + $1.pngData.count }
        output.append(try await DocumentPDFPageParser.recognize(prepared))
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        output.append(DocumentPDFPreparedPage(index: index, result: .init(warnings: [
          .init(code: .extractionFailed, message: "PDF page could not be extracted.",
                location: .init(page: index + 1))])))
      }
      progress?(.init(inputIndex: 0, phase: options.performOCR ? .recognizingText : .extracting,
        fractionCompleted: Double(index + 1) / Double(count)))
    }
    return output
  }
}
