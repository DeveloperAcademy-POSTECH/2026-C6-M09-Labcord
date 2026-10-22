import Foundation
import SwiftSoup

/// 내장 base64 그림과 기준 디렉터리 안의 상대 경로 그림만 OCR한다.
/// 원격 주소·절대 경로·기준 폴더 밖을 가리키는 참조는 자동으로 읽지 않는다.
nonisolated enum DocumentReferencedImageParser {
  static func recognize(
    _ reference: String,
    baseDirectory: URL?,
    options: DocumentParserOptions
  ) throws -> [DocumentBlock]? {
    guard
      let data = try imageData(
        for: reference, baseDirectory: baseDirectory, options: options)
    else { return nil }
    let image = try DocumentImageDecoder.decode(data, maximumPixels: options.maximumImagePixels)
    return try DocumentOCR.recognize(
      image: image.image,
      orientation: image.orientation,
      location: DocumentLocation(part: reference)
    )
  }

  static func references(in text: String, format: DocumentFormat) -> [String] {
    if format == .html {
      guard let document = try? SwiftSoup.parse(text),
        let images = try? document.select("img[src]")
      else { return [] }
      return images.compactMap { try? $0.attr("src") }.filter { !$0.isEmpty }
    }
    let pattern = "!\\[[^]]*\\]\\(([^ )]+)"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: range).compactMap { match in
      guard match.numberOfRanges > 1,
        let capture = Range(match.range(at: 1), in: text)
      else { return nil }
      return String(text[capture])
    }
  }

  /// 상대 경로는 심볼릭 링크를 해석한 뒤 기준 디렉터리 안에 있는지 다시 확인한다.
  private static func imageData(
    for reference: String,
    baseDirectory: URL?,
    options: DocumentParserOptions
  ) throws -> Data? {
    if reference.lowercased().hasPrefix("data:image/") {
      guard let comma = reference.firstIndex(of: ","),
        reference[..<comma].lowercased().hasSuffix(";base64")
      else { return nil }
      let encoded = reference[reference.index(after: comma)...].filter { !$0.isWhitespace }
      guard let data = Data(base64Encoded: encoded) else {
        throw DocumentParsingError.malformedDocument
      }
      guard data.count <= options.maximumInputBytes else {
        throw DocumentParsingError.inputTooLarge
      }
      return data
    }
    guard !reference.hasPrefix("//"),
      URLComponents(string: reference)?.scheme == nil,
      let baseDirectory
    else { return nil }
    let path = String(reference.split { $0 == "?" || $0 == "#" }.first ?? "")
    guard !path.isEmpty, !path.hasPrefix("/"),
      !path.split(separator: "/").contains("..")
    else { return nil }
    let root = baseDirectory.resolvingSymlinksInPath().standardizedFileURL
    let url = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
    guard url.path.hasPrefix(root.path + "/") else { return nil }
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    guard let size = values.fileSize, size >= 0 else { return nil }
    guard size <= options.maximumInputBytes else { throw DocumentParsingError.inputTooLarge }
    return try Data(contentsOf: url, options: [.mappedIfSafe])
  }
}
