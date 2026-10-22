import Foundation

/// 테스트에 필요한 작은 ZIP을 직접 만든다. 컨테이너의 필드 하나를 바꿔 위험 입력을 재현할 때도 사용한다.
struct DocumentArchiveFixtureBuilder {
  static func make(_ files: [(String, Data)]) -> Data {
    var output = Data()
    var directory = Data()
    for (name, contents) in files {
      let nameData = Data(name.utf8)
      let checksum = crc32(contents)
      let localOffset = UInt32(output.count)
      output.appendLE(UInt32(0x0403_4B50))
      output.appendLE(UInt16(20))
      output.appendLE(UInt16(0))
      output.appendLE(UInt16(0))
      output.appendLE(UInt16(0))
      output.appendLE(UInt16(0))
      output.appendLE(checksum)
      output.appendLE(UInt32(contents.count))
      output.appendLE(UInt32(contents.count))
      output.appendLE(UInt16(nameData.count))
      output.appendLE(UInt16(0))
      output.append(nameData)
      output.append(contents)

      directory.appendLE(UInt32(0x0201_4B50))
      directory.appendLE(UInt16(20))
      directory.appendLE(UInt16(20))
      directory.appendLE(UInt16(0))
      directory.appendLE(UInt16(0))
      directory.appendLE(UInt16(0))
      directory.appendLE(UInt16(0))
      directory.appendLE(checksum)
      directory.appendLE(UInt32(contents.count))
      directory.appendLE(UInt32(contents.count))
      directory.appendLE(UInt16(nameData.count))
      directory.appendLE(UInt16(0))
      directory.appendLE(UInt16(0))
      directory.appendLE(UInt16(0))
      directory.appendLE(UInt16(0))
      directory.appendLE(UInt32(0))
      directory.appendLE(localOffset)
      directory.append(nameData)
    }
    let directoryOffset = UInt32(output.count)
    output.append(directory)
    output.appendLE(UInt32(0x0605_4B50))
    output.appendLE(UInt16(0))
    output.appendLE(UInt16(0))
    output.appendLE(UInt16(files.count))
    output.appendLE(UInt16(files.count))
    output.appendLE(UInt32(directory.count))
    output.appendLE(directoryOffset)
    output.appendLE(UInt16(0))
    return output
  }

  private static func crc32(_ data: Data) -> UInt32 {
    var crc = UInt32.max
    for byte in data {
      crc ^= UInt32(byte)
      for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xEDB8_8320 : 0) }
    }
    return ~crc
  }
}

extension Data {
  fileprivate mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
    var littleEndian = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
  }
}
