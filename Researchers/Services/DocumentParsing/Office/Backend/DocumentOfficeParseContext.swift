import CoreGraphics
import Foundation
import ImageIO
import OdrCore
import SwiftSoup

/// OpenDocument.core의 문서 트리를 순회하며 블록·그림·경고를 누적한다.
/// 시트·슬라이드·페이지 이름은 part로 보존하되 백엔드가 주지 않은 기하 앵커를 만들지 않는다.
nonisolated struct DocumentOfficeParseContext {
  let options: DocumentParserOptions
  let format: DocumentFormat
  var blocks: [DocumentBlock] = []
  var warnings: [DocumentWarning] = []
  var images: [DocumentEmbeddedImage] = []
  var imageBytes = 0
  var imageAttempts = 0

  /// 문서 트리에서 셀을 얻지 못한 경우에만 로컬 HTML 변환 결과의 표를 보완 경로로 사용한다.
  mutating func extractSpreadsheetHTML(from decoded: DecodedFile) {
    do {
      let service = try HtmlTranslator.translate(file: decoded, config: HtmlConfig())
      for view in service.views {
        var resources: NSArray?
        let markup = try view.writeHtml(resources: &resources)
        let document = try SwiftSoup.parse(markup)
        for (tableIndex, table) in try document.select("table").enumerated() {
          let locationPart = "sheet[\(tableIndex + 1)]"
          blocks.append(
            DocumentBlock(
              kind: .table,
              text: "",
              readingOrder: blocks.count,
              location: DocumentLocation(part: locationPart)
            ))
          for (rowIndex, row) in try table.select("tr").enumerated() {
            for (columnIndex, cell) in try row.select("th, td").enumerated() {
              let text = try cell.text().trimmingCharacters(in: .whitespacesAndNewlines)
              guard !text.isEmpty else { continue }
              blocks.append(
                DocumentBlock(
                  kind: .tableCell,
                  text: text,
                  readingOrder: blocks.count,
                  location: DocumentLocation(
                    part: locationPart,
                    row: rowIndex + 1,
                    column: columnIndex + 1
                  )
                ))
            }
          }
        }
      }
    } catch {
      warnings.append(
        DocumentWarning(
          code: .extractionFailed,
          message: "Spreadsheet cells could not be rendered to a readable table.",
          location: DocumentLocation(part: format.rawValue)
        ))
    }
  }

  mutating func visit(_ element: OdrCore.Element, part: String?) throws {
    try Task.checkCancellation()
    let currentPart = childPart(element, inherited: part)
    if let table = element as? Table {
      appendTable(table, part: currentPart)
      for row in table.rows {
        for cell in row.children.compactMap({ $0 as? TableCell }) {
          try visitImages(in: cell, part: currentPart)
        }
      }
      return
    }
    if let cell = element as? SheetCell {
      let text = textContent(in: cell)
      if !text.isEmpty {
        blocks.append(
          DocumentBlock(
            kind: .tableCell,
            text: text,
            readingOrder: blocks.count,
            location: DocumentLocation(
              part: currentPart,
              row: Int(cell.position.row) + 1,
              column: Int(cell.position.column) + 1
            )
          ))
      }
      try visitImages(in: cell, part: currentPart)
      return
    }
    if let paragraph = element as? Paragraph {
      let text = textContent(in: paragraph)
      if !text.isEmpty {
        blocks.append(
          DocumentBlock(
            kind: .paragraph,
            text: text,
            readingOrder: blocks.count,
            location: DocumentLocation(part: currentPart)
          ))
      }
      try visitImages(in: paragraph, part: currentPart)
      return
    }
    if let image = element as? OdrCore.Image {
      try appendImage(image, part: currentPart)
      return
    }
    for child in element.children { try visit(child, part: currentPart) }
  }

  private mutating func appendTable(_ table: Table, part: String?) {
    blocks.append(
      DocumentBlock(
        kind: .table,
        text: "",
        readingOrder: blocks.count,
        location: DocumentLocation(part: part)
      ))
    for (rowIndex, row) in table.rows.enumerated() {
      for (columnIndex, cell) in row.children.compactMap({ $0 as? TableCell }).enumerated() {
        let text = textContent(in: cell)
        if !text.isEmpty {
          blocks.append(
            DocumentBlock(
              kind: .tableCell,
              text: text,
              readingOrder: blocks.count,
              location: DocumentLocation(
                part: part,
                row: rowIndex + 1,
                column: columnIndex + 1
              )
            ))
        }
      }
    }
  }

  /// 문단·셀에서 텍스트를 이미 읽었으므로 하위 트리는 그림만 순회해 본문 중복을 피한다.
  private mutating func visitImages(in element: OdrCore.Element, part: String?) throws {
    for child in element.children {
      try Task.checkCancellation()
      if let image = child as? OdrCore.Image {
        try appendImage(image, part: part)
      } else {
        try visitImages(in: child, part: part)
      }
    }
  }

  /// 문서 내부 그림만 읽는다. 디코딩·OCR 실패는 경고로 남기고 다른 요소의 처리는 계속한다.
  private mutating func appendImage(_ image: OdrCore.Image, part: String?) throws {
    try Task.checkCancellation()
    guard imageAttempts < options.maximumEmbeddedImages else {
      warnings.append(DocumentWarning(
        code: .resourceLimitReached,
        message: "Office image count exceeded the configured limit.",
        location: DocumentLocation(part: part ?? image.href)))
      return
    }
    imageAttempts += 1
    guard image.isInternal, let file = image.file,
      let data = try? file.data(), data.count <= options.maximumInputBytes
    else {
      warnings.append(
        DocumentWarning(
          code: .externalImageSkipped,
          message: "External or inaccessible Office image was skipped.",
          location: DocumentLocation(part: part ?? image.href)
        ))
      return
    }
    do {
      let decoded = try DocumentImageDecoder.decode(
        data, maximumPixels: options.maximumImagePixels)
      let recognized = try DocumentOCR.recognize(
        image: decoded.image,
        orientation: decoded.orientation,
        location: DocumentLocation(part: part ?? image.href)
      )
      retainImage(decoded.image, part: part ?? image.href, orientation: decoded.orientation)
      for var block in recognized {
        block.readingOrder = blocks.count
        blocks.append(block)
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      warnings.append(
        DocumentWarning(
          code: .imageOCRFailed,
          message: "Office image could not be decoded or recognized.",
          location: DocumentLocation(part: part ?? image.href)
        ))
    }
  }

  private mutating func retainImage(
    _ image: CGImage, part: String, orientation: CGImagePropertyOrientation
  ) {
    let location = DocumentLocation(part: part)
    guard let png = DocumentImageEncoder.png(image, orientation: orientation),
      png.count <= options.maximumExpandedBytes - imageBytes
    else {
      warnings.append(DocumentWarning(
        code: .resourceLimitReached, message: "Office image raster could not be retained.",
        location: location))
      return
    }
    images.append(DocumentEmbeddedImage(
      id: "\(part)/image[\(images.count)]", pngData: png, location: location,
      orientation: orientation))
    imageBytes += png.count
  }

  private func childPart(_ element: OdrCore.Element, inherited: String?) -> String? {
    if let slide = element as? Slide { return slide.name }
    if let sheet = element as? Sheet { return sheet.name }
    if let page = element as? Page { return page.name }
    return inherited
  }

  private func textContent(in element: OdrCore.Element) -> String {
    element.descendants(ofType: Text.self).map(\.content).joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
