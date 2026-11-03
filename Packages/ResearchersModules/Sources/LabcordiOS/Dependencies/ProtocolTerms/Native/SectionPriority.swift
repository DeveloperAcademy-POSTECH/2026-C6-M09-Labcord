// 고정 절차제목 순위화의 Swift 실험 구현. 모델·제품 기본 동작은 변경하지 않는다.
import Foundation

nonisolated struct PriorityRules: Decodable {
  let start: String
  let stop: String
  let maxHeadingScalars: Int
  let maxHeadingWords: Int
  nonisolated enum CodingKeys: String, CodingKey {
    case start, stop
    case maxHeadingScalars = "max_heading_scalars"
    case maxHeadingWords = "max_heading_words"
  }
}
nonisolated struct KoreanHeadingRules: Decodable {
  let start: String
  let stop: String
  let number: String
  let legal: String
  let maxKeyScalars: Int
  let legalWidth: Int
  nonisolated enum CodingKeys: String, CodingKey {
    case start, stop, number, legal
    case maxKeyScalars = "max_key_scalars"
    case legalWidth = "legal_width"
  }
}
nonisolated struct PriorityHeading: Codable, Equatable {
  let start: Int
  let end: Int
  let kind: String
  let heading: String
}
nonisolated struct ScalarRange: Equatable {
  let start: Int
  let end: Int
}
nonisolated struct RankingHint: Codable, Equatable {
  let text: String
  let start: Int
  let end: Int
  let score: Double
}
nonisolated struct CachedCandidate: Decodable {
  let start: Int
  let end: Int
  let score: Double
  let admitted: Bool
  let norm: String
  init(start: Int, end: Int, score: Double, admitted: Bool, norm: String) {
    self.start = start
    self.end = end
    self.score = score
    self.admitted = admitted
    self.norm = norm
  }

  init(from decoder: Decoder) throws {
    var localCandidate = try decoder.unkeyedContainer()
    start = try localCandidate.decode(Int.self)
    end = try localCandidate.decode(Int.self)
    score = try localCandidate.decode(Double.self)
    _ = try localCandidate.decode(Bool.self)
    _ = try localCandidate.decode(Bool.self)
    _ = try localCandidate.decode(String.self)
    _ = try localCandidate.decode(Int.self)
    admitted = try localCandidate.decode(Bool.self)
    norm = try localCandidate.decode(String.self)
    _ = try localCandidate.decode(String.self)
    guard localCandidate.isAtEnd else { throw RankingError.invalidCandidate }
  }
}
nonisolated enum RankingError: Error { case invalidCandidate, invalidSource, invalidReplay }

nonisolated struct SectionPriority {
  let rules: PriorityRules
  let begin: NSRegularExpression
  let end: NSRegularExpression
  let prefix: NSRegularExpression
  let koreanRules: KoreanHeadingRules?
  let extraBegin: NSRegularExpression?
  let extraEnd: NSRegularExpression?
  let extraNumber: NSRegularExpression?
  let extraLegal: NSRegularExpression?
  // Python str.split/re \s의 공백 집합을 명시해 Foundation 기본값과의 차이를 피한다.
  static let whitespacePattern =
    "[\\u0009-\\u000D\\u001C-\\u0020\\u0085\\u00A0\\u1680"
    + "\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000]"
  static func isWhitespace(_ localCandidate: Unicode.Scalar) -> Bool {
    switch localCandidate.value {
    case 9...13, 28...32, 133, 160, 5760, 8192...8202, 8232, 8233, 8239, 8287, 12288: return true
    default: return false
    }
  }
  init(rules: PriorityRules, koreanRules: KoreanHeadingRules? = nil) throws {
    self.rules = rules
    self.koreanRules = koreanRules
    func regex(_ pattern: String) throws -> NSRegularExpression {
      try NSRegularExpression(
        pattern: pattern.replacingOccurrences(of: "\\s", with: Self.whitespacePattern))
    }
    begin = try regex(rules.start)
    end = try regex(rules.stop)
    prefix = try regex("^(?:\\d+(?:\\.\\d+)*\\.?|[ivx]+\\.)\\s+")
    extraBegin = try koreanRules.map { try regex($0.start) }
    extraEnd = try koreanRules.map { try regex($0.stop) }
    extraNumber = try koreanRules.map { try regex($0.number) }
    extraLegal = try koreanRules.map { try regex($0.legal) }
  }
  func fullMatch(_ regex: NSRegularExpression, _ text: String) -> Bool {
    let all = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.firstMatch(in: text, range: all)?.range == all
  }
  func legalMatch(_ raw: String, width: Int) -> NSTextCheckingResult? {
    guard let localKr = koreanRules, width == localKr.legalWidth, let regex = extraLegal else {
      return nil
    }
    return regex.firstMatch(in: raw, range: NSRange(raw.startIndex..<raw.endIndex, in: raw))
  }
  func extraHeading(_ raw: String, width: Int) -> (String, Int)? {
    guard let localKr = koreanRules, let number = extraNumber, let begin = extraBegin,
      let end = extraEnd
    else { return nil }
    let title: String
    let prefixEnd: Int
    if let match = legalMatch(raw, width: width),
      let titleRange = Range(match.range(at: 1), in: raw),
      let fullRange = Range(match.range, in: raw) {
      title = String(raw[titleRange])
      prefixEnd = raw[..<fullRange.upperBound].unicodeScalars.count
    } else {
      let normalized = raw
        .decomposedStringWithCompatibilityMapping
        .precomposedStringWithCompatibilityMapping.lowercased()
      guard
        let localMiddle = number.firstMatch(
          in: normalized,
          range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)),
        let localResult = Range(localMiddle.range, in: normalized)
      else { return nil }
      title = String(normalized[localResult.upperBound...])
      prefixEnd = raw.unicodeScalars.count
    }
    let normalized = title
      .decomposedStringWithCompatibilityMapping
      .precomposedStringWithCompatibilityMapping.lowercased()
    let key = String(
      String.UnicodeScalarView(normalized.unicodeScalars.filter { !Self.isWhitespace($0) }))
    guard key.unicodeScalars.count <= localKr.maxKeyScalars else { return nil }
    if fullMatch(begin, key) { return ("procedure", prefixEnd) }
    if fullMatch(end, key) { return ("stop", prefixEnd) }
    return nil
  }
  func emit(
    _ candidates: [CachedCandidate], text: String, localLimit: Int, ranges: [ScalarRange] = []
  )
    throws -> [RankingHint] {
    guard localLimit > 0 else { return [] }
    let chars = Array(text.unicodeScalars)
    var seen: Set<String> = []
    var result: [RankingHint] = []
    for bucket in (ranges.isEmpty ? [0] : [1, 0]) {
      for localCandidate in candidates {
        guard localCandidate.start >= 0, localCandidate.end > localCandidate.start,
          localCandidate.end <= chars.count, localCandidate.score.isFinite
        else {
          throw RankingError.invalidCandidate
        }
        if !ranges.isEmpty {
          let inside = ranges.contains {
            localCandidate.start >= $0.start && localCandidate.end <= $0.end
          }
          if inside != (bucket == 1) { continue }
        }
        guard localCandidate.admitted, !localCandidate.norm.isEmpty,
          !seen.contains(localCandidate.norm)
        else { continue }
        seen.insert(localCandidate.norm)
        result.append(
          .init(
            text: String(
              String.UnicodeScalarView(chars[localCandidate.start..<localCandidate.end])),
            start: localCandidate.start,
            end: localCandidate.end, score: localCandidate.score))
        if result.count == localLimit { return result }
      }
    }
    return result
  }
  // 상수60은 Python 비교와 같고, gold/중요도 라벨은 입력받지 않는다.
  func emitFusion(
    _ candidates: [CachedCandidate], text: String, localLimit: Int, ranges: [ScalarRange]
  )
    throws -> [RankingHint] {
    guard localLimit > 0 else { return [] }
    if ranges.isEmpty { return try emit(candidates, text: text, localLimit: localLimit) }
    var baseline: [CachedCandidate] = []
    var baselineRanks: [String: Int] = [:]
    for localCandidate in candidates
      where localCandidate.admitted && !localCandidate.norm.isEmpty {
      if baselineRanks[localCandidate.norm] == nil {
        baseline.append(localCandidate)
        baselineRanks[localCandidate.norm] = baseline.count
      }
    }
    var sectionRanks: [String: Int] = [:]
    for bucket in [true, false] {
      for localCandidate in candidates
        where localCandidate.admitted && !localCandidate.norm.isEmpty {
        let inside = ranges.contains {
          localCandidate.start >= $0.start && localCandidate.end <= $0.end
        }
        if inside == bucket && sectionRanks[localCandidate.norm] == nil {
          sectionRanks[localCandidate.norm] = sectionRanks.count + 1
        }
      }
    }
    func reciprocal(_ localCandidate: CachedCandidate) -> Double {
      1 / Double(60 + baselineRanks[localCandidate.norm]!) + 1
        / Double(60 + sectionRanks[localCandidate.norm]!)
    }
    let fused = baseline.sorted {
      let localStart = reciprocal($0)
      let localEnd = reciprocal($1)
      return localStart == localEnd
        ? baselineRanks[$0.norm]! < baselineRanks[$1.norm]! : localStart > localEnd
    }
    return try emit(fused, text: text, localLimit: localLimit)
  }
}
