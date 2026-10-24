import Foundation
import OLEKit

/// HWP·구형 Office가 공유하는 CFB/OLE 컨테이너를 읽는다.
/// 스트림 이름으로 문서 종류를 구분하고, 깊이·항목 수·누적 바이트를 제한한다.
nonisolated enum DocumentCompoundFile {
  static func identify(_ data: Data) throws -> DocumentFormat {
    let file = try open(data)
    let names = Set(file.root.children.map(\.name))
    if names.contains("EncryptedPackage") { throw DocumentParsingError.encryptedDocument }
    if names.contains("FileHeader"), names.contains("BodyText") { return .hwp }
    if names.contains("WordDocument") { return .doc }
    if names.contains("Workbook") || names.contains("Book") { return .xls }
    if names.contains("PowerPoint Document") { return .ppt }
    throw DocumentParsingError.unsupportedFormat
  }

  static func streams(_ data: Data, options: DocumentParserOptions) throws -> [String: Data] {
    let file = try open(data)
    var output: [String: Data] = [:]
    var bytes = 0
    var count = 0
    func visit(_ entries: [DirectoryEntry], prefix: String, depth: Int) throws {
      guard depth <= 64 else { throw DocumentParsingError.inputTooLarge }
      for entry in entries {
        try Task.checkCancellation()
        count += 1
        guard count <= options.maximumArchiveEntries else {
          throw DocumentParsingError.inputTooLarge
        }
        let name = prefix.isEmpty ? entry.name : prefix + "/" + entry.name
        if entry.type == .stream {
          guard entry.streamSize <= UInt64(max(0, options.maximumExpandedBytes - bytes)) else {
            throw DocumentParsingError.inputTooLarge
          }
          let value = entry.streamSize == 0 ? Data() : try file.stream(entry).readDataToEnd()
          bytes += value.count
          output[name] = value
        } else {
          try visit(entry.children, prefix: name, depth: depth + 1)
        }
      }
    }
    try visit(file.root.children, prefix: "", depth: 0)
    return output
  }

  private static func open(_ data: Data) throws -> OLEFile {
    do {
      return try OLEFile(FileWrapper(regularFileWithContents: normalizeEmptyMiniFAT(data)))
    } catch {
      throw DocumentParsingError.malformedDocument
    }
  }

  /// OLEKit이 읽지 못하는 빈 MiniFAT 표현만 사본에서 보정한다. 유효한 스트림 데이터는 바꾸지 않는다.
  private static func normalizeEmptyMiniFAT(_ data: Data) -> Data {
    let reader = DocumentBinaryReader(data: data)
    guard reader.uint32(60) == 0xFFFF_FFFE, reader.uint32(64) == 0,
      let shift = reader.uint16(30), shift == 9 || shift == 12,
      let directory = reader.uint32(48)
    else { return data }
    let sectorSize = 1 << shift
    guard data.count >= sectorSize * 2, directory <= data.count / sectorSize - 2 else {
      return data
    }
    let root = (directory + 1) * sectorSize
    guard data[root + 66] == 5, reader.uint32(root + 120) == 0,
      reader.uint32(root + 124) == 0
    else { return data }
    // OLEKit 0.3.1은 유효한 빈 MiniFAT의 ENDOFCHAIN을 거부한다.
    // 읽기 전용 사본의 미사용 포인터만 바꾸며 원본과 실제 스트림은 보존한다.
    var normalized = data
    normalized.replaceSubrange(60..<64, with: [0, 0, 0, 0])
    return normalized
  }
}

/// 구형 바이너리 파서가 공유하는 little-endian 읽기 도우미. 범위를 벗어난 읽기는 nil이다.
nonisolated struct DocumentBinaryReader {
  let data: Data

  func uint16(_ offset: Int) -> Int? {
    guard offset >= 0, offset <= data.count - 2 else { return nil }
    return Int(data[offset]) | Int(data[offset + 1]) << 8
  }

  func uint32(_ offset: Int) -> Int? {
    guard let low = uint16(offset), let high = uint16(offset + 2) else { return nil }
    return low | high << 16
  }

  func slice(_ offset: Int, count: Int) -> Data? {
    guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else {
      return nil
    }
    return Data(data[offset..<offset + count])
  }
}
