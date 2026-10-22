import CoreFoundation
import Foundation

/// 바이트 시그니처 → 컨테이너 내부 구조 → 텍스트 내용 순으로 형식을 판별한다.
/// 파일명은 텍스트 형식의 힌트로만 사용하므로 확장자만 바꾼 바이너리를 신뢰하지 않는다.
nonisolated enum DocumentFormatDetector {
  static func detect(
    data: Data,
    fileName: String?,
    options: DocumentParserOptions = DocumentParserOptions()
  ) throws -> DocumentFormat {
    if let format = try detectSignature(data) { return format }
    if let format = try detectZipPackage(data, options: options) { return format }
    guard let text = decodeText(data) else { throw DocumentParsingError.unsupportedFormat }
    if let format = try detectTextFormat(text, fileName: fileName) { return format }
    throw DocumentParsingError.unsupportedFormat
  }

  /// BOM·UTF-16 패턴을 먼저 확인한다. 레거시 문자셋 선택은 휴리스틱이므로 완전한 판별은 아니다.
  static func decodeText(_ data: Data) -> String? {
    if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
      return String(data: data, encoding: .utf16)
    }
    if let encoding = utf16EncodingWithoutBOM(data) {
      return String(data: data, encoding: encoding)
    }
    if let text = String(data: data, encoding: .utf8) { return text }
    let asianCandidates = decodeAsianEncodings(data)
    if let bestCandidate = asianCandidates.max(by: { scriptScore($0) < scriptScore($1) }),
      scriptScore(bestCandidate) > 0 {
      return bestCandidate
    }
    return String(bytes: data, encoding: .windowsCP1252)
      ?? String(bytes: data, encoding: .isoLatin1)
  }

  private static func utf16EncodingWithoutBOM(_ data: Data) -> String.Encoding? {
    guard data.count >= 4, data.count.isMultiple(of: 2) else { return nil }
    let pairs = min(data.count, 4_096) / 2
    var evenZeros = 0
    var oddZeros = 0
    for pair in 0..<pairs {
      if data[pair * 2] == 0 { evenZeros += 1 }
      if data[pair * 2 + 1] == 0 { oddZeros += 1 }
    }
    if oddZeros * 4 >= pairs, oddZeros > evenZeros { return .utf16LittleEndian }
    if evenZeros * 4 >= pairs, evenZeros > oddZeros { return .utf16BigEndian }
    return nil
  }

  private static func detectSignature(_ data: Data) throws -> DocumentFormat? {
    if data.starts(with: [0x25, 0x50, 0x44, 0x46, 0x2D]) { return .pdf }
    if data.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
    if isTIFF(data) { return .tiff }
    if isHEIC(data) { return .heic }
    if data.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) {
      return try DocumentCompoundFile.identify(data)
    }
    if data.starts(with: [0xD7, 0xCD, 0xC6, 0x9A]) || isEMF(data) {
      throw DocumentParsingError.unsupportedFormat
    }
    return nil
  }

  private static func isTIFF(_ data: Data) -> Bool {
    data.starts(with: [0x49, 0x49, 0x2A, 0x00])
      || data.starts(with: [0x4D, 0x4D, 0x00, 0x2A])
  }

  private static func isHEIC(_ data: Data) -> Bool {
    guard data.count >= 12, data[4..<8].elementsEqual(Array("ftyp".utf8)) else { return false }
    let brand = String(data: data[8..<12], encoding: .ascii) ?? ""
    return ["heic", "heix", "hevc", "hevx", "mif1", "msf1"].contains(brand)
  }

  private static func isEMF(_ data: Data) -> Bool {
    data.count > 44 && data[40..<44].elementsEqual([0x20, 0x45, 0x4D, 0x46])
  }

  private static func decodeAsianEncodings(_ data: Data) -> [String] {
    ["windows-949", "EUC-KR", "Shift_JIS"].compactMap { charset in
      let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
      guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
      let encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
      return String(data: data, encoding: encoding)
    }
  }

  private static func detectTextFormat(
    _ text: String,
    fileName: String?
  ) throws -> DocumentFormat? {
    let trimmed = text.drop { $0.isWhitespace || $0 == "\u{FEFF}" }
    if trimmed.hasPrefix("{\\rtf") { return .rtf }
    let lowercased = trimmed.lowercased()
    if lowercased.hasPrefix("<svg") || lowercased.contains("<svg ") {
      throw DocumentParsingError.unsupportedFormat
    }
    if lowercased.hasPrefix("<!doctype html") || lowercased.hasPrefix("<html") { return .html }
    let extensionFormat = textFormat(for: fileName)
    if extensionFormat == .markdown, isPlausible(text) { return .markdown }
    if extensionFormat == .html, trimmed.first == "<" { return .html }
    if trimmed.hasPrefix("<?xml") || trimmed.first == "<" { return .xml }
    if isJSON(trimmed, source: text) { return .json }

    guard isPlausible(text) else { return nil }
    return extensionFormat ?? .txt
  }

  private static func isJSON(_ text: Substring, source: String) -> Bool {
    guard text.first == "{" || text.first == "[" else { return false }
    return
      (try? JSONSerialization.jsonObject(
        with: Data(source.utf8), options: [.fragmentsAllowed])) != nil
  }

  private static func textFormat(for fileName: String?) -> DocumentFormat? {
    let ext = URL(fileURLWithPath: fileName ?? "").pathExtension.lowercased()
    let byExtension: [String: DocumentFormat] = [
      "txt": .txt, "csv": .csv, "json": .json, "xml": .xml, "rtf": .rtf,
      "html": .html, "htm": .html, "md": .markdown, "markdown": .markdown
    ]
    return byExtension[ext]
  }

  /// ZIP인지 확인한 뒤 검증된 항목 이름으로 OOXML과 HWPX를 구분한다.
  private static func detectZipPackage(
    _ data: Data,
    options: DocumentParserOptions
  ) throws -> DocumentFormat? {
    guard
      data.starts(with: [0x50, 0x4B, 0x03, 0x04])
        || data.starts(with: [0x50, 0x4B, 0x05, 0x06])
    else { return nil }
    let names = try DocumentArchiveGuard.entryNames(in: data, options: options)
    if names.contains("word/document.xml") { return .docx }
    if names.contains("xl/workbook.xml") { return .xlsx }
    if names.contains("ppt/presentation.xml") { return .pptx }
    if names.contains("Contents/content.hpf") || names.contains("Contents/section0.xml") {
      return .hwpx
    }
    throw DocumentParsingError.unsupportedFormat
  }

  private static func scriptScore(_ text: String) -> Int {
    text.unicodeScalars.reduce(into: 0) { score, scalar in
      if (0xAC00...0xD7A3).contains(scalar.value) || (0x3040...0x30FF).contains(scalar.value) {
        score += 1
      }
    }
  }

  /// 디코딩됐다는 이유만으로 바이너리를 TXT로 취급하지 않도록 제어 문자 비율을 확인한다.
  private static func isPlausible(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    let controls = text.unicodeScalars.filter {
      CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\t"
    }
    return controls.count * 20 < text.unicodeScalars.count
  }
}
