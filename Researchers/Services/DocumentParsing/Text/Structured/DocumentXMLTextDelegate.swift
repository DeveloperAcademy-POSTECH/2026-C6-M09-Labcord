import Foundation

/// XML 요소 경로를 스택에 쌓고 텍스트 조각을 모아 블록을 만든다.
/// foundCharacters가 여러 번 호출돼도 요소 경계에 도달할 때까지 문자열을 이어 붙인다.
nonisolated final class XMLTextDelegate: NSObject, XMLParserDelegate {
  private var stack: [String] = []
  private var buffer = ""
  private(set) var blocks: [DocumentBlock] = []

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName: String?,
    attributes: [String: String]
  ) {
    flush()
    stack.append(elementName)
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    buffer.append(string)
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName: String?
  ) {
    flush()
    if !stack.isEmpty { stack.removeLast() }
  }

  private func flush() {
    let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.isEmpty {
      blocks.appendBlock(
        .paragraph, text: value, location: DocumentLocation(part: stack.joined(separator: "/")))
    }
    buffer = ""
  }
}
