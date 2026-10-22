import Foundation
import ImageIO

/// CFB 스트림의 OfficeArt 그림 레코드에서 지원되는 래스터 바이트를 찾는다.
/// 셀·도형의 기하 앵커 대신 스트림 이름과 바이트 위치를 원본 위치로 보존한다.
nonisolated enum DocumentLegacyImageExtractor {
  struct Image {
    let data: Data
    let part: String
  }

  static func extract(_ streams: [String: Data], limit: Int) -> [Image] {
    var result: [Image] = []
    for name in streams.keys.sorted()
    where ["Data", "WordDocument", "Pictures", "Workbook", "Book"].contains(name) {
      guard let original = streams[name] else { continue }
      let data = ["Workbook", "Book"].contains(name) ? drawingGroup(original) : original
      let reader = DocumentBinaryReader(data: data)
      var cursor = 0
      while cursor <= data.count - 8, result.count < limit {
        guard let type = reader.uint16(cursor + 2),
          [0xF01D, 0xF01E, 0xF029, 0xF02A].contains(type),
          let length = reader.uint32(cursor + 4), length >= 17,
          length <= data.count - cursor - 8
        else {
          cursor += 1
          continue
        }
        var extracted = false
        for prefix in [17, 33] where prefix + 4 <= length {
          let start = cursor + 8 + prefix
          let signature = data[start..<start + 4]
          if signature.starts(with: [0x89, 0x50, 0x4E, 0x47])
            || signature.starts(with: [0xFF, 0xD8, 0xFF])
            || signature.starts(with: [0x49, 0x49, 0x2A, 0]) {
            let bytes = Data(data[start..<cursor + 8 + length])
            result.append(Image(data: bytes, part: "\(name)/blip@\(cursor)"))
            extracted = true
            break
          }
        }
        cursor += extracted ? length + 8 : 1
      }
    }
    return result
  }

  /// Excel의 DrawingGroup 뒤에 이어진 CONTINUE 레코드를 붙여 OfficeArt 그림 데이터를 복원한다.
  private static func drawingGroup(_ workbook: Data) -> Data {
    let reader = DocumentBinaryReader(data: workbook)
    var cursor = 0
    var output = Data()
    var continuing = false
    while let type = reader.uint16(cursor), let length = reader.uint16(cursor + 2),
      let payload = reader.slice(cursor + 4, count: length) {
      if type == 0x00EB || (type == 0x003C && continuing) {
        output.append(payload)
        continuing = true
      } else {
        continuing = false
      }
      cursor += length + 4
    }
    return output
  }
}
