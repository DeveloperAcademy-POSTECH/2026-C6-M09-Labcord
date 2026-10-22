import CoreGraphics
import CoreHwp
import Foundation
import ImageIO

/// CoreHwp로 문서를 읽고 본문·표·그림과 복구 진단을 공통 모델에 담는다.
/// 읽기 가능한 부분을 복구해도 누락된 요소의 진단은 경고로 보존한다.
nonisolated enum DocumentHWPParser {
  static func parse(
    data: Data,
    format: DocumentFormat,
    options: DocumentParserOptions
  ) throws -> DocumentParseResult {
    let file = try loadFile(data, format: format, options: options)
    var context = DocumentHWPParseContext(options: options)
    context.binaryItems = file.binaryDataArray
    if format == .hwpx {
      do {
        context.descriptions = try DocumentHWPXDescriptions.read(data, options: options)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        context.warnings.append(DocumentWarning(
          code: (error as? DocumentParsingError) == .inputTooLarge
            ? .resourceLimitReached : .extractionFailed,
          message: "HWPX image descriptions could not be read.",
          location: DocumentLocation(part: "Contents")))
      }
    }
    try context.appendSections(file.displaySectionArray)
    try context.appendEmbeddedImages(file.binaryDataArray)
    context.appendDiagnostics(file.parseDiagnostics())

    return DocumentParseResult(
      format: format, blocks: context.blocks, warnings: context.warnings, images: context.images)
  }

  /// 원시 payload 보관은 끄고 제한된 부분 복구를 사용한다. 복구 진단은 parse에서 경고로 전달한다.
  private static func loadFile(
    _ data: Data,
    format: DocumentFormat,
    options: DocumentParserOptions
  ) throws -> HwpFile {
    if format == .hwpx { try DocumentArchiveGuard.validate(data, options: options) }
    let readLimits = HwpReadLimits(
      maxCompressedStreamBytes: options.maximumInputBytes,
      maxDecompressedStreamBytes: options.maximumExpandedBytes,
      maxAggregateStreamBytes: options.maximumExpandedBytes,
      maxNestingDepth: 64
    )
    let loadOptions = HwpLoadOptions(
      readLimits: readLimits,
      preserveRawPayload: false,
      recoverPartialContent: true
    )
    do {
      return try HwpFile(fromData: data, options: loadOptions)
    } catch let error as HwpError {
      throw mapError(error)
    } catch {
      throw DocumentParsingError.malformedDocument
    }
  }

  private static func mapError(_ error: HwpError) -> DocumentParsingError {
    switch error {
    case .unsupportedFeature(.encryptedDocument): return .encryptedDocument
    case .streamSizeLimitExceeded, .aggregateStreamSizeLimitExceeded: return .inputTooLarge
    default: return .malformedDocument
    }
  }

}
