import Foundation
import UIKit

nonisolated enum DocumentStructuredTextParser {
  static func parsePlainText(_ text: String) -> [DocumentBlock] {
    text.components(separatedBy: .newlines).enumerated().compactMap { index, line in
      let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { return nil }
      return DocumentBlock(
        kind: .paragraph,
        text: value,
        readingOrder: index,
        location: DocumentLocation(paragraph: index + 1)
      )
    }
  }

  static func parseJSON(_ text: String) -> [DocumentBlock] {
    guard let data = text.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    else {
      return parsePlainText(text)
    }
    var blocks: [DocumentBlock] = []
    func visit(_ value: Any, path: String) {
      if let dictionary = value as? [String: Any] {
        for key in dictionary.keys.sorted() {
          visit(dictionary[key] ?? NSNull(), path: path.isEmpty ? key : "\(path).\(key)")
        }
      } else if let array = value as? [Any] {
        for (index, child) in array.enumerated() {
          visit(child, path: "\(path)[\(index)]")
        }
      } else {
        let string: String
        if let value = value as? String {
          string = value
        } else if value is NSNull {
          string = "null"
        } else {
          string = String(describing: value)
        }
        blocks.append(
          DocumentBlock(
            kind: .paragraph,
            text: path.isEmpty ? string : "\(path): \(string)",
            readingOrder: blocks.count,
            location: DocumentLocation(part: path)
          ))
      }
    }
    visit(object, path: "")
    return blocks
  }

  static func parseXML(_ data: Data, fallbackText: String) -> [DocumentBlock] {
    let delegate = XMLTextDelegate()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    guard parser.parse() else { return parsePlainText(fallbackText) }
    return delegate.blocks
  }

  static func parseRTF(_ data: Data, fallbackText: String) -> [DocumentBlock] {
    do {
      let attributed = try NSAttributedString(
        data: data,
        options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil
      )
      return parsePlainText(attributed.string)
    } catch {
      return parsePlainText(fallbackText)
    }
  }
}
