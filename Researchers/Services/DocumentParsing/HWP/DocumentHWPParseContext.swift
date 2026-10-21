import CoreGraphics
import CoreHwp
import Foundation
import ImageIO

nonisolated struct DocumentHWPParseContext {
  let options: DocumentParserOptions
  var blocks: [DocumentBlock] = []
  var warnings: [DocumentWarning] = []
  var images: [DocumentEmbeddedImage] = []
  var imageBytes = 0
  var imageAttempts = 0
  var binaryItems: [HwpBinaryData] = []
  var descriptions: [UInt32: String] = [:]
  var visitedImages: Set<String> = []

  mutating func appendSections(_ sections: [HwpSection]) throws {
    for (sectionIndex, section) in sections.enumerated() {
      for (paragraphIndex, paragraph) in section.paragraph.enumerated() {
        try Task.checkCancellation()
        try append(
          paragraph,
          location: DocumentLocation(
            part: "section[\(sectionIndex)]",
            paragraph: paragraphIndex + 1
          )
        )
      }
    }
  }

  mutating func appendDiagnostics(_ diagnostics: [HwpParseDiagnostic]) {
    for diagnostic in diagnostics {
      let isRecovered =
        diagnostic.kind == .recoveredParagraph
        || diagnostic.kind == .recoveredSection
        || diagnostic.kind == .recoveredMemoParagraph
      warnings.append(
        DocumentWarning(
          code: isRecovered ? .extractionFailed : .unsupportedElement,
          message: "Some HWP/HWPX elements could not be represented in the extracted result.",
          location: DocumentLocation(part: diagnostic.path)
        ))
    }
  }

  mutating func append(_ paragraph: HwpParagraph, location: DocumentLocation) throws {
    let text = paragraphText(paragraph)
    if !text.isEmpty {
      blocks.append(
        DocumentBlock(
          kind: .paragraph,
          text: text,
          readingOrder: blocks.count,
          location: location
        )
      )
    }
    try appendControls(paragraph, location: location)
  }

  mutating func append(_ table: HwpTable, part: String?) throws {
    blocks.append(
      DocumentBlock(
        kind: .table,
        text: "",
        readingOrder: blocks.count,
        location: DocumentLocation(part: part)
      ))
    for (index, cell) in table.cellArray.enumerated() {
      let value = cell.paragraphArray.map(paragraphText)
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
      let row = cell.header.cellProperty.map { Int($0.rowAddress) + 1 } ?? index + 1
      let column = Int(cell.header.cellProperty?.columnAddress ?? 0) + 1
      let location = DocumentLocation(
        part: part, row: row, column: column,
        rowSpan: cell.header.cellProperty.map { max(1, Int($0.rowSpan)) },
        columnSpan: cell.header.cellProperty.map { max(1, Int($0.columnSpan)) })
      if !value.isEmpty {
        blocks.append(DocumentBlock(
          kind: .tableCell, text: value, readingOrder: blocks.count, location: location))
      }
      for (paragraphIndex, paragraph) in cell.paragraphArray.enumerated() {
        var source = location
        source.paragraph = paragraphIndex + 1
        try appendControls(paragraph, location: source)
      }
    }
  }

  mutating func appendControls(_ paragraph: HwpParagraph, location: DocumentLocation) throws {
    for (index, control) in (paragraph.ctrlHeaderArray ?? []).enumerated() {
      try Task.checkCancellation()
      var parent = location.part ?? "section"
      if let row = location.row, let column = location.column {
        parent += "/cell[\(row),\(column)]"
      }
      var anchor = location
      anchor.part = "\(parent)/paragraph[\(location.paragraph ?? 0)]"
        + "/control[\(index)]"
      switch control {
      case .table(let table):
        let part = "\(parent)/paragraph[\(location.paragraph ?? 0)]"
          + "/table[\(index)]"
        try append(table, part: part)
      case .picture(let shape), .shape(let shape), .container(let shape):
        try appendPictures(shape.shapeComponentArray,
                           property: shape.commonCtrlProperty, location: anchor)
      case .genShapeObject(let shape):
        try appendPictures(shape.shapeComponentArray,
                           property: shape.commonCtrlProperty, location: anchor)
      default: break
      }
    }
  }

  func paragraphText(_ paragraph: HwpParagraph) -> String {
    let units = (paragraph.paraText?.charArray ?? []).compactMap { character -> UInt16? in
      if character.value == 9 { return 9 }
      if character.value == 30 || character.value == 31 { return 32 }
      guard character.type == .char, character.value != 0 else { return nil }
      return character.value
    }
    return String(decoding: units, as: UTF16.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
