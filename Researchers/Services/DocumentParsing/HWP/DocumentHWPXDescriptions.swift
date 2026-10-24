import Foundation

/// CoreHwp가 합성 unknown record에서 버리는 그림 설명을 원본 XML에서 보완한다.
/// 설명은 OCR 텍스트가 아니라 그림의 원본 메타데이터다.
/// XML의 개체 ID로 설명을 연결하며 서로 충돌하는 설명과 엔티티 선언은 거부한다.
nonisolated enum DocumentHWPXDescriptions {
  /// 외부 엔티티 해석을 끄는 것에 더해 UTF-8·16·32의 DTD·엔티티 선언 자체도 거부한다.
  static func read(_ data: Data, options: DocumentParserOptions) throws -> [UInt32: String] {
    let entries = try DocumentArchiveReader.xmlEntries(data, options: options)
    var result: [UInt32: String] = [:]
    for (_, xml) in entries {
      try Task.checkCancellation()
      let declarationEncodings: [String.Encoding] = [
        .utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian
      ]
      for keyword in ["<!DOCTYPE", "<!ENTITY"] {
        for encoding in declarationEncodings {
          if let token = keyword.data(using: encoding), xml.range(of: token) != nil {
            throw DocumentParsingError.malformedDocument
          }
        }
      }
      let delegate = DescriptionDelegate()
      let parser = XMLParser(data: xml)
      parser.shouldProcessNamespaces = true
      parser.shouldResolveExternalEntities = false
      parser.delegate = delegate
      guard parser.parse() else {
        try Task.checkCancellation()
        throw DocumentParsingError.malformedDocument
      }
      for (id, text) in delegate.descriptions {
        guard result[id] == nil || result[id] == text else {
          throw DocumentParsingError.malformedDocument
        }
        result[id] = text
      }
    }
    return result
  }
}

nonisolated private final class DescriptionDelegate: NSObject, XMLParserDelegate {
  var descriptions: [UInt32: String] = [:]
  var pictures: [(depth: Int, id: UInt32)] = []
  var depth = 0
  var descriptionDepth: Int?
  var text = ""
  private let paragraphNamespace = "http://www.hancom.co.kr/hwpml/2011/paragraph"

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    depth += 1
    guard depth <= 64, !Task.isCancelled else { parser.abortParsing(); return }
    guard namespaceURI == paragraphNamespace else { return }
    if elementName == "pic", let id = UInt32(attributes["instid"] ?? attributes["id"] ?? "") {
      pictures.append((depth, id))
    }
    if elementName == "shapeComment", !pictures.isEmpty {
      descriptionDepth = depth
      text = ""
    }
  }

  func parser(
    _ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?
  ) {
    parser.abortParsing()
  }

  func parser(
    _ parser: XMLParser, foundExternalEntityDeclarationWithName name: String,
    publicID: String?, systemID: String?
  ) {
    parser.abortParsing()
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if descriptionDepth != nil { text += string }
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName: String?
  ) {
    if descriptionDepth == depth, let picture = pictures.last {
      if let previous = descriptions[picture.id], previous != text {
        parser.abortParsing()
        return
      }
      descriptions[picture.id] = text
      descriptionDepth = nil
    }
    if pictures.last?.depth == depth { pictures.removeLast() }
    depth -= 1
  }
}
