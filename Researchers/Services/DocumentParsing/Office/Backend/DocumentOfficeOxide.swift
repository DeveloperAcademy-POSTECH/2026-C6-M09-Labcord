import Foundation
import OfficeOxide

/// C 핸들과 반환 문자열은 문서 호출 안에서 해제한다. 그림은 기존 OfficeArt 복구 경로를 사용한다.
nonisolated enum DocumentOfficeOxide {
  static func parse(_ data: Data, format: DocumentFormat) throws -> [DocumentBlock] {
    try Task.checkCancellation()
    var error: Int32 = 0
    let handle = data.withUnsafeBytes {
      office_document_open_from_bytes($0.bindMemory(to: UInt8.self).baseAddress,
                                      $0.count, format.rawValue, &error)
    }
    guard let handle else { throw DocumentParsingError.malformedDocument }
    defer { office_document_free(handle) }
    guard let json = office_document_to_ir_json(handle, &error) else {
      throw DocumentParsingError.malformedDocument
    }
    defer { office_oxide_free_string(json) }
    let value = try JSONSerialization.jsonObject(with: Data(bytes: json, count: strlen(json)))
    guard let object = value as? [String: Any],
      let sections = object["sections"] as? [[String: Any]]
    else { throw DocumentParsingError.malformedDocument }
    var blocks: [DocumentBlock] = []
    for (index, section) in sections.enumerated() {
      var table = 0
      try visit(section["elements"] as? [[String: Any]] ?? [],
                part: format == .doc ? "WordDocument" : "slide[\(index + 1)]",
                table: &table, blocks: &blocks)
    }
    return blocks
  }

  private static func visit(_ elements: [[String: Any]], part: String, table: inout Int,
                            blocks: inout [DocumentBlock]) throws {
    for element in elements {
      try Task.checkCancellation()
      if element["type"] as? String == "table" {
        let path = part == "WordDocument" ? "WordDocument/table" : "\(part)/table[\(table)]"
        table += 1
        blocks.appendBlock(.table, location: .init(part: path))
        for (row, value) in (element["rows"] as? [[String: Any]] ?? []).enumerated() {
          for (column, cell) in (value["cells"] as? [[String: Any]] ?? []).enumerated() {
            blocks.appendBlock(.tableCell, text: text(cell["content"]),
                               location: .init(part: path, row: row + 1, column: column + 1))
          }
        }
      } else if let items = element["items"] as? [[String: Any]] {
        for item in items {
          var children = item["content"] as? [[String: Any]] ?? []
          if var nested = item["nested"] as? [String: Any] {
            nested["type"] = "list"
            children.append(nested)
          }
          try visit(children, part: part, table: &table, blocks: &blocks)
        }
      } else {
        let value = text(element["content"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
          blocks.appendBlock(.paragraph, text: value, location: .init(part: part))
        }
      }
    }
  }

  private static func text(_ value: Any?) -> String {
    if let string = value as? String { return string }
    return (value as? [[String: Any]] ?? []).map {
      if $0["type"] as? String == "line_break" { return "\n" }
      return $0["text"] as? String ?? text($0["content"])
    }.joined()
  }
}
