import CoreGraphics
import Foundation
import ImageIO
import OdrCore

/// OpenDocument.core의 문서 트리를 순회하며 블록·그림·경고를 누적한다.
/// 시트·슬라이드·페이지 이름은 part로 보존하되 백엔드가 주지 않은 기하 앵커를 만들지 않는다.
nonisolated struct DocumentOfficeParseContext {
  let options: DocumentParserOptions
  var blocks: [DocumentBlock] = []
  var warnings: [DocumentWarning] = []
  var images: [DocumentEmbeddedImage] = []
  var imageBytes = 0
  var imageAttempts = 0

  // Swift 바인딩은 셀의 희소 순회 API를 제공하지 않으므로 좌표 조회 수를 문서 전체에서 제한한다.
  private var inspectedCells = 0

  private mutating func appendCells(_ sheet: Sheet) throws {
    let size = sheet.contentDimensions()
    guard size.rows > 0, size.columns > 0 else { return }
    let location = DocumentLocation(part: sheet.name)
    blocks.appendBlock(.table, location: location)
    for row in 0..<size.rows {
      for column in 0..<size.columns {
        try Task.checkCancellation()
        guard inspectedCells < 100_000 else {
          warnings.append(DocumentWarning(
            code: .resourceLimitReached, message: "Spreadsheet cell visit limit exceeded.",
            location: DocumentLocation(part: sheet.name, row: Int(row) + 1,
                                       column: Int(column) + 1)))
          return
        }
        inspectedCells += 1
        if let cell = sheet.cell(column: column, row: row) {
          try visit(cell, part: sheet.name)
        }
      }
    }
  }

  mutating func visit(_ element: OdrCore.Element, part: String?) throws {
    try Task.checkCancellation()
    let currentPart = childPart(element, inherited: part)
    if let sheet = element as? Sheet {
      try appendCells(sheet)
      for shape in sheet.shapes { try visit(shape, part: sheet.name) }
      return
    }
    if let table = element as? Table {
      appendTable(table, part: currentPart)
      for row in table.rows {
        for cell in row.children.compactMap({ $0 as? TableCell }) {
          try visitImages(in: cell, part: currentPart)
        }
      }
      return
    }
    // 셀과 문단은 같은 텍스트·그림 경로를 사용하고 셀 주소만 별도로 보존한다.
    let cell = element as? SheetCell
    if cell != nil || element is Paragraph {
      if cell?.isCovered == true { return }
      let text = textContent(in: element)
      if !text.isEmpty {
        blocks.appendBlock(
          cell == nil ? .paragraph : .tableCell, text: text,
          location: DocumentLocation(
            part: currentPart, row: cell.map { Int($0.position.row) + 1 },
            column: cell.map { Int($0.position.column) + 1 },
            rowSpan: cell.flatMap { $0.span.rows > 1 ? Int($0.span.rows) : nil },
            columnSpan: cell.flatMap { $0.span.columns > 1 ? Int($0.span.columns) : nil }))
      }
      try visitImages(in: element, part: currentPart)
      return
    }
    if let image = element as? OdrCore.Image {
      try appendImage(image, part: currentPart)
      return
    }
    for child in element.children { try visit(child, part: currentPart) }
  }

  private mutating func appendTable(_ table: Table, part: String?) {
    blocks.appendBlock(.table, location: DocumentLocation(part: part))
    for (rowIndex, row) in table.rows.enumerated() {
      for (columnIndex, cell) in row.children.compactMap({ $0 as? TableCell }).enumerated() {
        let text = textContent(in: cell)
        if !text.isEmpty {
          blocks.appendBlock(
            .tableCell, text: text,
            location: DocumentLocation(part: part, row: rowIndex + 1, column: columnIndex + 1))
        }
      }
    }
  }

  /// 문단·셀에서 텍스트를 이미 읽었으므로 하위 트리는 그림만 순회해 본문 중복을 피한다.
  private mutating func visitImages(in element: OdrCore.Element, part: String?) throws {
    guard options.extractImages || options.performOCR else { return }
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
    guard options.extractImages || options.performOCR else { return }
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
      let recognized = try options.performOCR ? DocumentOCR.recognize(
        image: decoded.image,
        orientation: decoded.orientation,
        location: DocumentLocation(part: part ?? image.href)
      ) : []
      if options.extractImages {
        retainImage(decoded.image, part: part ?? image.href, orientation: decoded.orientation)
      }
      blocks.appendInReadingOrder(recognized)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      warnings.append(
        DocumentWarning(
          code: options.performOCR ? .imageOCRFailed : .extractionFailed,
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
    blocks.appendBlock(.image, location: location)
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
