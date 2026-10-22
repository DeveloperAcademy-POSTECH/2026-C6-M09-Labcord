import Foundation

/// CSV의 인용·개행을 해석해 행과 셀 위치를 보존한다.
/// 값을 수식이나 숫자로 계산하지 않고 원문 문자열로 반환한다.
nonisolated enum DocumentCSVParser {
  static func parseCSV(_ text: String) -> [DocumentBlock] {
    let rows = csvRows(text)
    var blocks: [DocumentBlock] = []
    var order = 0
    for (rowIndex, row) in rows.enumerated() {
      blocks.append(
        DocumentBlock(
          kind: .table,
          text: "",
          readingOrder: order,
          location: DocumentLocation(row: rowIndex + 1)
        ))
      order += 1
      for (columnIndex, value) in row.enumerated() {
        blocks.append(
          DocumentBlock(
            kind: .tableCell,
            text: value,
            readingOrder: order,
            location: DocumentLocation(row: rowIndex + 1, column: columnIndex + 1)
          ))
        order += 1
      }
    }
    return blocks
  }

  /// 인용 필드 안의 쉼표·개행은 값으로 보존하고, 연속된 두 따옴표는 따옴표 하나로 해석한다.
  private static func csvRows(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    let characters = Array(text)
    var index = 0
    while index < characters.count {
      let character = characters[index]
      if quoted {
        if character == "\"" {
          if index + 1 < characters.count, characters[index + 1] == "\"" {
            index += 1
            field.append("\"")
          } else {
            quoted = false
          }
        } else {
          field.append(character)
        }
      } else {
        switch character {
        case "\"" where field.isEmpty: quoted = true
        case ",":
          row.append(field)
          field = ""
        case "\n", "\r\n", "\r":
          row.append(field)
          rows.append(row)
          row = []
          field = ""
        default: field.append(character)
        }
      }
      index += 1
    }
    if !field.isEmpty || !row.isEmpty {
      row.append(field)
      rows.append(row)
    }
    return rows
  }
}
