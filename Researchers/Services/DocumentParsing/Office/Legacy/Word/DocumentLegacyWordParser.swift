import Foundation

/// 구형 Word의 piece table을 따라 본문을 복원하고 셀·행 제어 문자를 해석한다.
/// 복잡한 중첩·병합 표의 전체 조판을 복원하는 파서는 아니다.
nonisolated enum DocumentLegacyWordParser {
  static func parse(_ streams: [String: Data]) -> [DocumentBlock]? {
    guard let body = streams["WordDocument"] else { return nil }
    let reader = DocumentBinaryReader(data: body)
    guard reader.uint16(0) == 0xA5EC, let flags = reader.uint16(10),
      let table = streams[flags & 0x0200 == 0 ? "0Table" : "1Table"],
      let words = reader.uint16(32), let longs = reader.uint16(34 + words * 2)
    else { return nil }
    let pairs = 38 + words * 2 + longs * 4
    guard let offset = reader.uint32(pairs + 33 * 8),
      let length = reader.uint32(pairs + 33 * 8 + 4),
      let clx = DocumentBinaryReader(data: table).slice(offset, count: length),
      let text = pieceText(clx, document: reader)
    else { return nil }
    return blocks(text)
  }

  /// piece마다 압축 플래그에 따라 1바이트 문자와 UTF-16을 구분하고 본문 문자 길이까지만 읽는다.
  private static func pieceText(_ clx: Data, document: DocumentBinaryReader) -> String? {
    let reader = DocumentBinaryReader(data: clx)
    var cursor = 0
    while cursor < clx.count, clx[cursor] == 1 {
      guard let length = reader.uint16(cursor + 1), length <= clx.count - cursor - 3 else {
        return nil
      }
      cursor += length + 3
    }
    guard cursor < clx.count, clx[cursor] == 2,
      let length = reader.uint32(cursor + 1), length >= 4, (length - 4) % 12 == 0,
      let pieces = reader.slice(cursor + 5, count: length)
    else { return nil }
    let count = (length - 4) / 12
    let table = DocumentBinaryReader(data: pieces)
    guard let bodyLength = document.uint32(76) else { return nil }
    var output = ""
    for index in 0..<count {
      guard let start = table.uint32(index * 4), let end = table.uint32((index + 1) * 4),
        end >= start, let encoded = table.uint32((count + 1) * 4 + index * 8 + 2)
      else { return nil }
      if start >= bodyLength { break }
      let compressed = encoded & 0x4000_0000 != 0
      let offset = (encoded & 0x3FFF_FFFF) / (compressed ? 2 : 1)
      let characters = min(end, bodyLength) - start
      guard let bytes = document.slice(offset, count: characters * (compressed ? 1 : 2)),
        let text = String(data: bytes, encoding: compressed ? .windowsCP1252 : .utf16LittleEndian)
      else { return nil }
      output += text
    }
    return output
  }

  private static func blocks(_ text: String) -> [DocumentBlock] {
    let characters = Array(text)
    var output: [DocumentBlock] = []
    var buffer = ""
    var cells: [String] = []
    var row = 0
    for (index, character) in characters.enumerated() {
      if character == "\u{7}" {
        if buffer.isEmpty, !cells.isEmpty {
          row += 1
          appendRow(cells, row: row, to: &output)
          cells = []
        } else {
          cells.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
          buffer = ""
        }
      } else if character == "\r", cells.isEmpty,
        index + 1 == characters.count || characters[index + 1] != "\u{7}" {
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
          output.append(
            DocumentBlock(
              kind: .paragraph, text: value, readingOrder: output.count,
              location: DocumentLocation(part: "WordDocument")))
        }
        buffer = ""
        row = 0
      } else if character == "\r" {
        buffer += "\n"
      } else if character.unicodeScalars.allSatisfy({ $0.value >= 32 || $0 == "\t" }) {
        buffer.append(character)
      }
    }
    if !cells.isEmpty { appendRow(cells, row: row + 1, to: &output) }
    return output
  }

  private static func appendRow(_ cells: [String], row: Int, to blocks: inout [DocumentBlock]) {
    if row == 1 {
      blocks.append(
        DocumentBlock(
          kind: .table, text: "", readingOrder: blocks.count,
          location: DocumentLocation(part: "WordDocument/table")))
    }
    for (column, text) in cells.enumerated() {
      blocks.append(
        DocumentBlock(
          kind: .tableCell, text: text, readingOrder: blocks.count,
          location: DocumentLocation(
            part: "WordDocument/table",
            row: row, column: column + 1)))
    }
  }
}
