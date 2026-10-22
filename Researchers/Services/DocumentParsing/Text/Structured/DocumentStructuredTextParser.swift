import Foundation
import UIKit

/// 일반 텍스트·JSON·XML·RTF를 공통 문단 블록으로 바꾼다.
/// 구조를 읽지 못한 경우 원문 텍스트로 복구하며, 각 형식의 전체 표현을 재현하지는 않는다.
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

  /// 객체 키는 정렬해 안정된 순서를 만든다. 원본 JSON의 키 배치 순서를 복원하는 기능은 아니다.
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
        blocks.appendBlock(
          .paragraph, text: path.isEmpty ? string : "\(path): \(string)",
          location: DocumentLocation(part: path))
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

  /// Foundation이 제공한 본문 문자열만 사용한다. RTF 고유 표·그림 구조는 여기서 복원하지 않는다.
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
