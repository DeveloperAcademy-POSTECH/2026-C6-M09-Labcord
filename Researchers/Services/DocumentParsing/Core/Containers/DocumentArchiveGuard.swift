import Foundation

/// ZIP을 열기 전에 중앙 디렉터리의 크기·경로·암호화 여부를 검사한다.
/// 선언된 크기 검증과 실제 압축 해제량 검증은 별개이며, 후자는 ArchiveReader에서도 확인한다.
nonisolated enum DocumentArchiveGuard {
  private static let endSignature: UInt32 = 0x0605_4B50
  private static let entrySignature: UInt32 = 0x0201_4B50

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
    guard data.count >= 22 else { throw DocumentParsingError.malformedDocument }
    let lowerBound = max(0, data.count - 65_557)
    let endOffset = stride(from: data.count - 22, through: lowerBound, by: -1).first {
      readUInt32(data, $0) == endSignature
        && Int(readUInt16(data, $0 + 20) ?? 0) == data.count - $0 - 22
    }
    guard let endOffset,
      readUInt16(data, endOffset + 4) == 0,
      readUInt16(data, endOffset + 6) == 0,
      let entryCount = readUInt16(data, endOffset + 10),
      readUInt16(data, endOffset + 8) == entryCount,
      let directorySize = readUInt32(data, endOffset + 12),
      let directoryOffset = readUInt32(data, endOffset + 16)
    else { throw DocumentParsingError.malformedDocument }
    let start = Int(directoryOffset)
    let end = start + Int(directorySize)
    guard start >= 0, end == endOffset, end >= start else {
      throw DocumentParsingError.malformedDocument
    }
    return ArchiveDirectory(entryCount: Int(entryCount), start: start, end: end)
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
      guard entry.compressedSize != UInt32.max, entry.uncompressedSize != UInt32.max else {
        throw DocumentParsingError.inputTooLarge
      }
      let (totalBytes, overflow) = expandedBytes.addingReportingOverflow(
        Int(entry.uncompressedSize)
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
    guard offset + 46 <= directoryEnd,
      readUInt32(data, offset) == entrySignature,
      let flags = readUInt16(data, offset + 8),
      let compressedSize = readUInt32(data, offset + 20),
      let uncompressedSize = readUInt32(data, offset + 24),
      let nameLength = readUInt16(data, offset + 28),
      let extraLength = readUInt16(data, offset + 30),
      let commentLength = readUInt16(data, offset + 32)
    else { throw DocumentParsingError.malformedDocument }
    let nameStart = offset + 46
    let nameEnd = nameStart + Int(nameLength)
    let nextOffset = nameEnd + Int(extraLength) + Int(commentLength)
    guard nextOffset <= directoryEnd,
      let name = String(data: data[nameStart..<nameEnd], encoding: .utf8)
    else { throw DocumentParsingError.malformedDocument }
    return CentralDirectoryEntry(
      method: readUInt16(data, offset + 10) ?? UInt16.max,
      checksum: readUInt32(data, offset + 16) ?? 0,
      localOffset: Int(readUInt32(data, offset + 42) ?? UInt32.max),
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
    let method: UInt16
    let checksum: UInt32
    let localOffset: Int
    let flags: UInt16
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let name: String
    let nextOffset: Int
  }

  private static func safeArchivePath(_ path: String) -> Bool {
    !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0")
      && !path.split(separator: "/").contains { $0 == ".." || $0 == "." || $0.contains(":") }
  }

  private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16? {
    guard offset >= 0, offset + 2 <= data.count else { return nil }
    return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
  }

  private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32? {
    guard offset >= 0, offset + 4 <= data.count else { return nil }
    return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
      | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
  }
}
