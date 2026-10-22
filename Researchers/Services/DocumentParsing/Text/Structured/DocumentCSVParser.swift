import Foundation

/// CSV의 인용·개행을 해석해 행과 셀 위치를 보존한다.
/// 값을 수식이나 숫자로 계산하지 않고 원문 문자열로 반환한다.
nonisolated enum DocumentCSVParser {
  /// 인용 필드 안의 쉼표·개행은 값으로 보존하고, 두 따옴표는 따옴표 하나로 해석한다.
  static func parseCSV(_ text: String) -> [DocumentBlock] {
    var blocks: [DocumentBlock] = []
    var rowIndex = 1
    var row: [String] = []
    var field = ""
    var quoted = false
    // 전체 Character 배열 없이 한 문자만 미리 읽는다. CRLF와 조합 문자 단위를 보존한다.
    var iterator = text.makeIterator()
    var next = iterator.next()
    while let character = next {
      next = iterator.next()
      if quoted {
        if character == "\"" {
          if next == "\"" {
            next = iterator.next()
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
          blocks.appendTableRow(row, row: rowIndex)
          rowIndex += 1
          row.removeAll(keepingCapacity: true)
          field = ""
        default: field.append(character)
        }
      }
    }
    if !field.isEmpty || !row.isEmpty {
      row.append(field)
      blocks.appendTableRow(row, row: rowIndex)
    }
    return blocks
  }
}
