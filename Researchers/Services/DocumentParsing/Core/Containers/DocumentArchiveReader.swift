import Foundation
import zlib

/// ZIP의 XML 파트만 메모리에서 읽는다. 실제 inflate 출력에도 상한을 적용한다.
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
      let expected = Int(entry.uncompressedSize)
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
      guard UInt32(checksum) == entry.checksum else {
        throw DocumentParsingError.malformedDocument
      }
      remaining -= bytes.count
      result.append((entry.name, bytes))
    }
    return result
  }

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
    let finish = start + Int(entry.compressedSize)
    guard start <= end, finish <= end,
      reader.uint16(offset + 8) == Int(entry.method),
      reader.uint16(offset + 6) == Int(entry.flags),
      String(data: data[(offset + 30)..<(offset + 30 + nameLength)], encoding: .utf8)
        == entry.name
    else { throw DocumentParsingError.malformedDocument }
    return Data(data[start..<finish])
  }

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
