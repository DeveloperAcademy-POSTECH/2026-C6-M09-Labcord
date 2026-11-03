import Foundation

/// 문서 기반 개발자료에서 비교하는 순위 전략. 실제 STT 효용을 의미하지 않는다.
nonisolated public enum TermHintRanking: Equatable {
  case nativeFusion
  case guardedFrequency
}

nonisolated struct DocumentFrequencyRanking {
  nonisolated private struct Span: Hashable {
    let start: Int
    let end: Int
  }

  nonisolated private struct RankedHint {
    let hint: RankingHint
    let position: Int
    let score: Double
  }

  /// 상위 75개 안에서만 순서를 바꾸며 같은 위치의 겹침 후보는 한 번만 센다.
  static func hints(
    candidates: [CachedCandidate], fusion: [RankingHint], text: String, limit: Int
  ) throws -> [RankingHint] {
    guard limit > 0 else { return [] }
    let scalars = Array(text.unicodeScalars)
    let head = Array(fusion.prefix(75))
    let headKeys = Set(head.map { HintNorm.norm($0.text) })
    var spans: [String: Set<Span>] = [:]
    for candidate in candidates where candidate.admitted && headKeys.contains(candidate.norm) {
      guard candidate.start >= 0, candidate.end > candidate.start,
        candidate.end <= scalars.count, candidate.score.isFinite
      else { throw RankingError.invalidCandidate }
      spans[candidate.norm, default: []].insert(Span(start: candidate.start, end: candidate.end))
    }
    var ranked: [RankedHint] = []
    for (position, hint) in head.enumerated() {
      let key = HintNorm.norm(hint.text)
      let spanCount: Int = spans[key]?.count ?? 0
      ranked.append(RankedHint(
        hint: hint, position: position, score: adjustedScore(hint, spanCount: spanCount)))
    }
    ranked.sort { left, right in
      left.score == right.score ? left.position < right.position : left.score > right.score
    }
    // 보정 점수는 정렬에만 쓰고 표면·위치·모델 점수는 그대로 반환한다.
    return Array((ranked.map { $0.hint } + fusion.dropFirst(head.count)).prefix(limit))
  }

  private static func adjustedScore(_ hint: RankingHint, spanCount: Int) -> Double {
    let key = HintNorm.norm(hint.text)
    let hasHangul = hint.text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
    let shortPenalty: Double = hasHangul && key.unicodeScalars.count <= 2 ? 0.05 : 0.0
    let cappedCount: Int = Swift.min(spanCount, 4)
    let bonus: Double = 0.005 * log1p(Double(cappedCount))
    return hint.score + bonus - shortPenalty
  }
}
