import Foundation

nonisolated enum DocumentMarkdownParser {
  static func parseMarkdown(_ text: String) -> [DocumentBlock] {
    let lines = text.components(separatedBy: .newlines)
    var blocks: [DocumentBlock] = []
    var lineIndex = 0
    while lineIndex < lines.count {
      let value = lines[lineIndex].trimmingCharacters(in: .whitespaces)
      guard !value.isEmpty else {
        lineIndex += 1
        continue
      }
      if let table = parseTable(lines, startingAt: lineIndex) {
        for var block in table.blocks {
          block.readingOrder = blocks.count
          blocks.append(block)
        }
        lineIndex = table.nextLineIndex
        continue
      }
      let headingCount = value.prefix { $0 == "#" }.count
      let isHeading = (1...6).contains(headingCount) && value.dropFirst(headingCount).first == " "
      let content = isHeading ? String(value.dropFirst(headingCount + 1)) : value
      let cleaned = content.replacingOccurrences(
        of: "!\\[([^]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
      if !cleaned.isEmpty {
        blocks.append(
          DocumentBlock(
            kind: isHeading ? .heading : .paragraph,
            text: cleaned,
            readingOrder: blocks.count,
            location: DocumentLocation(
              part: isHeading ? "heading-\(headingCount)" : nil, paragraph: lineIndex + 1)
          ))
      }
      lineIndex += 1
    }
    return blocks
  }

  private static func parseTable(
    _ lines: [String],
    startingAt start: Int
  ) -> (blocks: [DocumentBlock], nextLineIndex: Int)? {
    guard start + 1 < lines.count,
      lines[start].contains("|"),
      isMarkdownTableSeparator(lines[start + 1])
    else { return nil }

    var rows: [[String]] = []
    var lineIndex = start
    while lineIndex < lines.count, lines[lineIndex].contains("|") {
      let row = tableCells(lines[lineIndex])
      if !row.isEmpty, !isMarkdownTableSeparator(lines[lineIndex]) { rows.append(row) }
      lineIndex += 1
    }

    var blocks: [DocumentBlock] = []
    for (rowIndex, row) in rows.enumerated() {
      blocks.append(
        DocumentBlock(
          kind: .table,
          text: "",
          readingOrder: blocks.count,
          location: DocumentLocation(row: rowIndex + 1)
        ))
      for (columnIndex, cell) in row.enumerated() {
        blocks.append(
          DocumentBlock(
            kind: .tableCell,
            text: cell,
            readingOrder: blocks.count,
            location: DocumentLocation(row: rowIndex + 1, column: columnIndex + 1)
          ))
      }
    }
    return (blocks, lineIndex)
  }

  private static func isMarkdownTableSeparator(_ line: String) -> Bool {
    let cells = tableCells(line)
    return !cells.isEmpty
      && cells.allSatisfy { cell in
        let value = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return value.count >= 3 && value.allSatisfy { $0 == "-" }
      }
  }

  private static func tableCells(_ line: String) -> [String] {
    var value = line.trimmingCharacters(in: .whitespaces)
    if value.hasPrefix("|") { value.removeFirst() }
    if value.hasSuffix("|") { value.removeLast() }
    return value.split(separator: "|", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
  }
}
