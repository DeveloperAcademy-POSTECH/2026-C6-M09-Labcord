import Foundation

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
    if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { flush() }
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
    if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { flush() }
    if !stack.isEmpty { stack.removeLast() }
  }

  private func flush() {
    let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.isEmpty {
      blocks.append(
        DocumentBlock(
          kind: .paragraph,
          text: value,
          readingOrder: blocks.count,
          location: DocumentLocation(part: stack.joined(separator: "/"))
        ))
    }
    buffer = ""
  }
}
