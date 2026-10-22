import Foundation

/// ZIP을 열기 전에 중앙 디렉터리의 크기·경로·암호화 여부를 검사한다.
/// 선언된 크기 검증과 실제 압축 해제량 검증은 별개이며, 후자는 ArchiveReader에서도 확인한다.
nonisolated enum DocumentArchiveGuard {
  private static let endSignature = 0x0605_4B50
  private static let entrySignature = 0x0201_4B50

  static func validate(_ data: Data, options: DocumentParserOptions) throws {
    _ = try entryNames(in: data, options: options)
  }

  static func entryNames(in data: Data, options: DocumentParserOptions) throws -> Set<String> {
    let directory = try readDirectory(data)
    guard directory.entryCount <= options.maximumArchiveEntries else {
      throw DocumentParsingError.inputTooLarge
    }
    return try validateEntries(
      data,
      directory: directory,
      maximumExpandedBytes: options.maximumExpandedBytes
    )
  }

  /// ZIP 끝 레코드를 뒤에서 찾는다. 주석 길이와 디렉터리 경계가 실제 입력 크기와 맞아야 한다.
  static func readDirectory(_ data: Data) throws -> ArchiveDirectory {
    let reader = DocumentBinaryReader(data: data)
    guard data.count >= 22 else { throw DocumentParsingError.malformedDocument }
    let lowerBound = max(0, data.count - 65_557)
    let endOffset = stride(from: data.count - 22, through: lowerBound, by: -1).first {
      reader.uint32($0) == endSignature
        && (reader.uint16($0 + 20) ?? 0) == data.count - $0 - 22
    }
    guard let endOffset,
      reader.uint16(endOffset + 4) == 0,
      reader.uint16(endOffset + 6) == 0,
      let entryCount = reader.uint16(endOffset + 10),
      reader.uint16(endOffset + 8) == entryCount,
      let directorySize = reader.uint32(endOffset + 12),
      let directoryOffset = reader.uint32(endOffset + 16)
    else { throw DocumentParsingError.malformedDocument }
    let start = directoryOffset
    let end = start + directorySize
    guard start >= 0, end == endOffset, end >= start else {
      throw DocumentParsingError.malformedDocument
    }
    return ArchiveDirectory(entryCount: entryCount, start: start, end: end)
  }

  /// 항목 수·해제 크기를 누적하고 중복 경로와 경로 탈출을 거부한다.
  private static func validateEntries(
    _ data: Data,
    directory: ArchiveDirectory,
    maximumExpandedBytes: Int
  ) throws -> Set<String> {
    var cursor = directory.start
    var processedEntries = 0
    var expandedBytes = 0
    var names: Set<String> = []
    for _ in 0..<directory.entryCount where cursor < directory.end {
      let entry = try readEntry(data, at: cursor, directoryEnd: directory.end)
      guard entry.flags & 0x0001 == 0 else { throw DocumentParsingError.encryptedDocument }
      guard entry.compressedSize != Int(UInt32.max),
        entry.uncompressedSize != Int(UInt32.max) else {
        throw DocumentParsingError.inputTooLarge
      }
      let (totalBytes, overflow) = expandedBytes.addingReportingOverflow(
        entry.uncompressedSize
      )
      guard !overflow, totalBytes <= maximumExpandedBytes else {
        throw DocumentParsingError.inputTooLarge
      }
      expandedBytes = totalBytes
      guard safeArchivePath(entry.name), names.insert(entry.name).inserted
      else { throw DocumentParsingError.malformedDocument }
      cursor = entry.nextOffset
      processedEntries += 1
    }
    guard processedEntries == directory.entryCount, cursor == directory.end else {
      throw DocumentParsingError.malformedDocument
    }
    return names
  }

  static func readEntry(
    _ data: Data,
    at offset: Int,
    directoryEnd: Int
  ) throws -> CentralDirectoryEntry {
    let reader = DocumentBinaryReader(data: data)
    guard offset + 46 <= directoryEnd,
      reader.uint32(offset) == entrySignature,
      let flags = reader.uint16(offset + 8),
      let compressedSize = reader.uint32(offset + 20),
      let uncompressedSize = reader.uint32(offset + 24),
      let nameLength = reader.uint16(offset + 28),
      let extraLength = reader.uint16(offset + 30),
      let commentLength = reader.uint16(offset + 32)
    else { throw DocumentParsingError.malformedDocument }
    let nameStart = offset + 46
    let nameEnd = nameStart + nameLength
    let nextOffset = nameEnd + extraLength + commentLength
    guard nextOffset <= directoryEnd,
      let name = String(data: data[nameStart..<nameEnd], encoding: .utf8)
    else { throw DocumentParsingError.malformedDocument }
    return CentralDirectoryEntry(
      method: reader.uint16(offset + 10) ?? Int(UInt16.max),
      checksum: reader.uint32(offset + 16) ?? 0,
      localOffset: reader.uint32(offset + 42) ?? Int(UInt32.max),
      flags: flags,
      compressedSize: compressedSize,
      uncompressedSize: uncompressedSize,
      name: name,
      nextOffset: nextOffset
    )
  }

  struct ArchiveDirectory {
    let entryCount: Int
    let start: Int
    let end: Int
  }

  struct CentralDirectoryEntry {
    let method: Int
    let checksum: Int
    let localOffset: Int
    let flags: Int
    let compressedSize: Int
    let uncompressedSize: Int
    let name: String
    let nextOffset: Int
  }

  private static func safeArchivePath(_ path: String) -> Bool {
    !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0")
      && !path.split(separator: "/").contains { $0 == ".." || $0 == "." || $0.contains(":") }
  }

}
