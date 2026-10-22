import CryptoKit
import Foundation

@testable import Researchers

/// 본문이나 이미지 바이트를 로그에 남기지 않고 결과의 모든 의미 필드를 비교한다.
/// 비교에 필요한 위치·메타데이터·PNG 전체를 순서대로 해시한다. 본문이나 그림 바이트를 로그로 노출하지 않는다.
nonisolated enum DocumentResultFingerprint {
  static func blocks(_ blocks: [DocumentBlock]) -> String {
    var hash = SHA256()
    for block in blocks {
      append(block.kind.rawValue, to: &hash)
      append(block.text, to: &hash)
      append(String(block.readingOrder), to: &hash)
      append(block.location, to: &hash)
      append(block.ocrConfidence.map { String($0.bitPattern) }, to: &hash)
      append(block.ocrOriginalText, to: &hash)
    }
    return digest(hash)
  }

  static func images(_ images: [DocumentEmbeddedImage]) -> String {
    var hash = SHA256()
    for image in images {
      append(image.id, to: &hash)
      append(image.location, to: &hash)
      append(String(image.orientation.rawValue), to: &hash)
      append(image.sourceDescription, to: &hash)
      append(String(image.pngData.count), to: &hash)
      hash.update(data: image.pngData)
    }
    return digest(hash)
  }

  static func warnings(_ warnings: [DocumentWarning]) -> String {
    var hash = SHA256()
    for warning in warnings {
      append(warning.code.rawValue, to: &hash)
      append(warning.message, to: &hash)
      append(warning.location, to: &hash)
    }
    return digest(hash)
  }

  private static func append(_ location: DocumentLocation?, to hash: inout SHA256) {
    append(location == nil ? nil : "location", to: &hash)
    guard let location else { return }
    append(location.part, to: &hash)
    for value in [location.page, location.row, location.column, location.paragraph,
                  location.rowSpan, location.columnSpan] {
      append(value.map(String.init), to: &hash)
    }
    append(location.bounds == nil ? nil : "bounds", to: &hash)
    if let bounds = location.bounds {
      for value in [bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height] {
        append(String(Double(value).bitPattern), to: &hash)
      }
    }
  }

  private static func append(_ value: String?, to hash: inout SHA256) {
    guard let value else { hash.update(data: Data([0])); return }
    hash.update(data: Data([1]))
    let bytes = Data(value.utf8)
    var length = UInt64(bytes.count).bigEndian
    withUnsafeBytes(of: &length) { hash.update(bufferPointer: $0) }
    hash.update(data: bytes)
  }

  private static func digest(_ hash: SHA256) -> String {
    hash.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
