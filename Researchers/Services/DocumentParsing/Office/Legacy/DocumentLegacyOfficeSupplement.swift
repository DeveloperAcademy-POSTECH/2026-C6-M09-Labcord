import Foundation
import ImageIO

/// 백엔드 결과에 구형 Word 표·PPT 그룹 표·OfficeArt 그림을 보완한다.
/// 원본 스트림 위치는 남기지만 본문과 그림의 정확한 인라인 순서는 확정하지 않는다.
nonisolated enum DocumentLegacyOfficeSupplement {
  static func extract(
    data: Data, format: DocumentFormat, base: DocumentParseResult, options: DocumentParserOptions,
    inspectedImages: Int
  ) throws -> DocumentParseResult {
    let streams = try DocumentCompoundFile.streams(data, options: options)
    var context = Context(blocks: base.blocks, images: base.images, warnings: base.warnings,
                          options: options, bytes: base.images.reduce(0) { $0 + $1.pngData.count })
    if format == .doc, let word = DocumentLegacyWordParser.parse(streams), !word.isEmpty {
      context.blocks = word
    }
    if format == .ppt { try context.appendTables(streams) }
    let extracted = DocumentLegacyImageExtractor.extract(
      streams, limit: max(0, options.maximumEmbeddedImages - inspectedImages))
    for image in extracted { try context.append(image) }
    if let image = context.images.first {
      context.warnings.append(DocumentWarning(
        code: .uncertainReadingOrder,
        message: "Legacy Office pictures retain stream locations; "
          + "inline anchors may be incomplete.",
        location: image.location))
    }
    return DocumentParseResult(format: format, blocks: context.blocks,
                               warnings: context.warnings, images: context.images)
  }

  private struct Context {
    var blocks: [DocumentBlock]
    var images: [DocumentEmbeddedImage]
    var warnings: [DocumentWarning]
    let options: DocumentParserOptions
    var bytes: Int

    mutating func append(_ image: DocumentLegacyImageExtractor.Image) throws {
      try Task.checkCancellation()
      let location = DocumentLocation(part: image.part)
      guard images.count < options.maximumEmbeddedImages else {
        warnings.append(DocumentWarning(
          code: .resourceLimitReached, message: "Legacy Office picture count exceeded the limit.",
          location: location))
        return
      }
      do {
        let decoded = try DocumentImageDecoder.decode(
          image.data, maximumPixels: options.maximumImagePixels)
        if let png = DocumentImageEncoder.png(decoded.image, orientation: decoded.orientation) {
          if images.contains(where: { $0.pngData == png }) { return }
          if png.count <= options.maximumExpandedBytes - bytes {
            images.append(DocumentEmbeddedImage(
              id: image.part, pngData: png, location: location, orientation: decoded.orientation))
            bytes += png.count
          } else {
            warnings.append(DocumentWarning(
              code: .resourceLimitReached,
              message: "Legacy Office picture bytes exceeded the limit.",
              location: location))
          }
        }
        let recognized = try DocumentOCR.recognize(
          image: decoded.image, orientation: decoded.orientation, location: location)
        blocks.append(DocumentBlock(
          kind: .image, text: "", readingOrder: blocks.count, location: location))
        for var block in recognized where !blocks.contains(where: {
          $0.kind == .imageOCR && $0.text == block.text
        }) {
          block.readingOrder = blocks.count
          blocks.append(block)
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        warnings.append(DocumentWarning(
          code: .imageOCRFailed, message: "Legacy Office picture could not be decoded.",
          location: location))
      }
    }

    mutating func appendTables(_ streams: [String: Data]) throws {
      let tables = try DocumentPPTTableParser.parse(streams)
      for var block in tables {
        block.readingOrder = blocks.count
        blocks.append(block)
      }
      if let table = tables.first {
        warnings.append(DocumentWarning(
          code: .uncertainReadingOrder,
          message: "PPT grouped table cells follow backend text; inline ordering is approximate.",
          location: table.location))
      }
    }
  }
}
