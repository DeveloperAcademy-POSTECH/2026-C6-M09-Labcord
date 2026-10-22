import Foundation

/// 구형 PPT의 길이 기반 레코드를 경계 검사와 함께 읽는다.
/// 편집 이력을 따라 현재 슬라이드만 찾으므로 이전 편집본을 중복 슬라이드로 읽지 않는다.
nonisolated struct DocumentPPTRecords {
  struct Record {
    let type: Int
    let instance: Int
    let container: Bool
    let start: Int
    let end: Int
  }

  let reader: DocumentBinaryReader

  func record(at offset: Int) throws -> Record {
    guard let flags = reader.uint16(offset), let type = reader.uint16(offset + 2),
      let length = reader.uint32(offset + 4), offset >= 0,
      offset <= reader.data.count - 8, length <= reader.data.count - offset - 8
    else { throw DocumentParsingError.malformedDocument }
    return Record(
      type: type, instance: flags >> 4, container: flags & 15 == 15,
      start: offset + 8, end: offset + 8 + length)
  }

  func children(of record: Record) throws -> [Record] {
    var cursor = record.start
    var output: [Record] = []
    while cursor < record.end {
      let child = try self.record(at: cursor)
      guard child.end <= record.end, output.count < 100_000 else {
        throw DocumentParsingError.malformedDocument
      }
      output.append(child)
      cursor = child.end
    }
    return output
  }

  func descendants(of record: Record, type: Int, depth: Int = 0) throws -> [Record] {
    guard depth < 32 else { throw DocumentParsingError.inputTooLarge }
    try Task.checkCancellation()
    var output: [Record] = []
    for child in try children(of: record) {
      if child.type == type { output.append(child) }
      if child.container || child.type == 0xF00D {
        output.append(contentsOf: try descendants(of: child, type: type, depth: depth + 1))
      }
    }
    return output
  }

  /// 최신 편집부터 persist ID 매핑을 채워 현재 문서가 참조하는 슬라이드만 반환한다.
  func liveSlides(currentUser: Data) throws -> [Record] {
    guard var edit = DocumentBinaryReader(data: currentUser).uint32(16) else {
      throw DocumentParsingError.malformedDocument
    }
    var directory: [Int: Int] = [:]
    var documentID: Int?
    var visited: Set<Int> = []
    while edit != 0 {
      guard visited.count < 64, visited.insert(edit).inserted else {
        throw DocumentParsingError.malformedDocument
      }
      let record = try self.record(at: edit)
      guard record.type == 4085, record.end - record.start >= 28,
        let previous = reader.uint32(record.start + 8),
        let persist = reader.uint32(record.start + 12),
        let identifier = reader.uint32(record.start + 16)
      else { throw DocumentParsingError.malformedDocument }
      documentID = documentID ?? identifier
      try addDirectory(at: persist, to: &directory)
      guard previous == 0 || previous < edit else { throw DocumentParsingError.malformedDocument }
      edit = previous
    }
    guard let documentID, let offset = directory[documentID] else {
      throw DocumentParsingError.malformedDocument
    }
    let document = try record(at: offset)
    var slides: [Record] = []
    for list in try children(of: document) where list.type == 4080 && list.instance == 0 {
      for persist in try children(of: list) where persist.type == 1011 {
        guard let identifier = reader.uint32(persist.start), let offset = directory[identifier]
        else {
          throw DocumentParsingError.malformedDocument
        }
        let slide = try record(at: offset)
        guard slide.type == 1006 else { throw DocumentParsingError.malformedDocument }
        slides.append(slide)
      }
    }
    return slides
  }

  private func addDirectory(at offset: Int, to directory: inout [Int: Int]) throws {
    let record = try self.record(at: offset)
    guard record.type == 6002 else { throw DocumentParsingError.malformedDocument }
    var cursor = record.start
    while cursor < record.end {
      guard let entry = reader.uint32(cursor) else { throw DocumentParsingError.malformedDocument }
      let count = entry >> 20
      let identifier = entry & 0xFFFFF
      guard count > 0, count * 4 <= record.end - cursor - 4 else {
        throw DocumentParsingError.malformedDocument
      }
      cursor += 4
      for index in 0..<count {
        guard let offset = reader.uint32(cursor + index * 4) else {
          throw DocumentParsingError.malformedDocument
        }
        if directory[identifier + index] == nil { directory[identifier + index] = offset }
      }
      cursor += count * 4
    }
  }
}
