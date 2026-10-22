import Foundation
import zlib

/// ZIP의 XML 파트만 메모리에서 읽는다. 실제 inflate 출력에도 상한을 적용한다.
/// 파일 시스템에 풀지 않고 검증된 XML 항목만 읽는다.
/// 중앙 디렉터리와 로컬 헤더가 일치하고 CRC가 맞아야 항목을 채택한다.
nonisolated enum DocumentArchiveReader {
  static func xmlEntries(
    _ data: Data, options: DocumentParserOptions
  ) throws -> [(String, Data)] {
    try DocumentArchiveGuard.validate(data, options: options)
    let directory = try DocumentArchiveGuard.readDirectory(data)
    var cursor = directory.start
    var remaining = options.maximumExpandedBytes
    var result: [(String, Data)] = []
    for _ in 0..<directory.entryCount {
      try Task.checkCancellation()
      let entry = try DocumentArchiveGuard.readEntry(
        data, at: cursor, directoryEnd: directory.end)
      cursor = entry.nextOffset
      guard entry.name.hasSuffix(".xml") else { continue }
      let packed = try compressedBytes(data, entry: entry, end: directory.start)
      let expected = entry.uncompressedSize
      guard expected <= remaining else { throw DocumentParsingError.inputTooLarge }
      let bytes: Data
      switch entry.method {
      case 0: bytes = packed
      case 8: bytes = try expand(packed, limit: expected)
      default: throw DocumentParsingError.unsupportedFormat
      }
      guard bytes.count == expected else { throw DocumentParsingError.malformedDocument }
      let checksum = bytes.withUnsafeBytes { buffer in
        crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count))
      }
      guard Int(checksum) == entry.checksum else {
        throw DocumentParsingError.malformedDocument
      }
      remaining -= bytes.count
      result.append((entry.name, bytes))
    }
    return result
  }

  /// 로컬 헤더의 이름·압축 방식·플래그를 중앙 디렉터리와 대조한 뒤 해당 바이트만 자른다.
  private static func compressedBytes(
    _ data: Data, entry: DocumentArchiveGuard.CentralDirectoryEntry, end: Int
  ) throws -> Data {
    let reader = DocumentBinaryReader(data: data)
    let offset = entry.localOffset
    guard offset >= 0, offset <= end - 30,
      reader.uint32(offset) == 0x0403_4B50
    else { throw DocumentParsingError.malformedDocument }
    let nameLength = Int(reader.uint16(offset + 26) ?? 0)
    let extraLength = Int(reader.uint16(offset + 28) ?? 0)
    let start = offset + 30 + nameLength + extraLength
    let finish = start + entry.compressedSize
    guard start <= end, finish <= end,
      reader.uint16(offset + 8) == entry.method,
      reader.uint16(offset + 6) == entry.flags,
      String(data: data[(offset + 30)..<(offset + 30 + nameLength)], encoding: .utf8)
        == entry.name
    else { throw DocumentParsingError.malformedDocument }
    return Data(data[start..<finish])
  }

  /// ZIP의 raw DEFLATE를 작은 버퍼로 해제한다. 선언된 크기보다 출력이 커지면 즉시 중단한다.
  private static func expand(_ data: Data, limit: Int) throws -> Data {
    var stream = z_stream()
    guard inflateInit2_(
      &stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK
    else { throw DocumentParsingError.malformedDocument }
    defer { inflateEnd(&stream) }
    return try data.withUnsafeBytes { input in
      stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
      stream.avail_in = uInt(input.count)
      var output = Data()
      var buffer = [UInt8](repeating: 0, count: 65_536)
      while true {
        try Task.checkCancellation()
        let status = buffer.withUnsafeMutableBytes { bytes -> Int32 in
          stream.next_out = bytes.bindMemory(to: Bytef.self).baseAddress
          stream.avail_out = uInt(bytes.count)
          return inflate(&stream, Z_NO_FLUSH)
        }
        let count = buffer.count - Int(stream.avail_out)
        guard count <= limit - output.count else { throw DocumentParsingError.inputTooLarge }
        output.append(contentsOf: buffer.prefix(count))
        if status == Z_STREAM_END {
          guard stream.avail_in == 0 else { throw DocumentParsingError.malformedDocument }
          return output
        }
        guard status == Z_OK, count > 0 else { throw DocumentParsingError.malformedDocument }
      }
    }
  }
}
