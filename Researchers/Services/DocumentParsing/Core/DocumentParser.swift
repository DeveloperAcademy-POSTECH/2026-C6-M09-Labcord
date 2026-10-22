import CoreGraphics
import Foundation
import ImageIO

/// 화면과 독립된 문서 파싱 진입점이다. 형식별 파서는 이 타입을 통해 호출한다.
/// 로컬 입력을 텍스트·블록·그림·경고로 반환하며 파일 형식 변환이나 저장은 수행하지 않는다.
nonisolated public enum DocumentParser {
  /// 진행 이벤트는 작업 스레드에서 호출될 수 있다. UI 갱신은 호출 측에서 MainActor로 전달한다.
  public typealias ProgressHandler = @Sendable (DocumentProgress) -> Void

  /// 문서 하나를 읽는다. 입력의 보안 접근과 OCR 세션은 이 호출이 끝날 때까지 유지한다.
  /// - Parameters:
  ///   - input: 로컬 URL, 파일명 힌트가 있는 Data, 또는 방향이 지정된 CGImage.
  ///   - options: 문서별 입력 크기·그림·페이지 작업 한도.
  ///   - progress: 선택적 진행 콜백. MainActor에서 실행된다고 가정하면 안 된다.
  /// - Returns: 본문·블록·그림·복구 가능한 실패 경고를 포함한 결과.
  /// - Throws: 열기·형식·암호화 오류. 취소는 DocumentParsingError.cancelled로 정규화한다.
  @concurrent public static func parse(
    _ input: DocumentInput,
    options: DocumentParserOptions = DocumentParserOptions(),
    progress: ProgressHandler? = nil
  ) async throws -> DocumentParseResult {
    try await DocumentOCR.$sessions.withValue(DocumentOCRSessionPool()) {
      try await parseInput(input, index: 0, options: options, progress: progress)
    }
  }

  /// 모든 형식의 성공 외 종료 경로를 모아 실패·취소 진행 이벤트를 일관되게 보낸다.
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
    let format = try prepared.image != nil ? DocumentFormat.image : DocumentFormatDetector.detect(
      data: prepared.data, fileName: prepared.fileName, options: options)
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

  /// URL 입력만 기준 디렉터리를 보존한다. Data의 파일명은 로컬 참조 그림을 읽을 권한이 아니다.
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

  private static func parse(
    prepared: PreparedInput,
    format: DocumentFormat,
    options: DocumentParserOptions,
    progress: ProgressHandler?
  ) async throws -> DocumentParseResult {
    if let (image, orientation) = prepared.image {
      if options.performOCR {
        progress?(DocumentProgress(
          inputIndex: 0, phase: .recognizingText, fractionCompleted: 0.25))
      }
      return try DocumentRasterParser.parseImage(
        image, orientation: orientation, format: .image, location: .init(), options: options)
    }
    let data = prepared.data
    switch format {
    case .jpeg, .png, .heic, .tiff:
      return try DocumentRasterParser.parse(
        data, format: format, options: options, progress: progress)
    case .txt, .csv, .json, .xml, .rtf, .html, .markdown:
      return try await DocumentTextParser.parse(
        data,
        format: format,
        baseDirectory: prepared.baseDirectory,
        options: options
      )
    case .pdf:
      return try await DocumentPDFParser.parse(data, options: options, progress: progress)
    case .docx, .xlsx, .pptx, .doc, .xls, .ppt:
      throw DocumentParsingError.unsupportedFormat
    case .hwp, .hwpx:
      throw DocumentParsingError.unsupportedFormat
    case .image:
      throw DocumentParsingError.unsupportedFormat
    }
  }

}
