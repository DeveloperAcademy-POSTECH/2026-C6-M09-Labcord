import Foundation

nonisolated enum HintNorm {
  static let particles: [String] = [
    "으로", "에서", "에게", "께서", "까지", "부터", "인데", "에는", "이고", "이며",
    "이", "가", "은", "는", "을", "를", "의", "에", "로", "도", "만", "와", "과", "랑", "며", "고", "처럼", "보다"
  ]
  static func norm(_ localString: String) -> String {
    let localCount = localString
      .decomposedStringWithCompatibilityMapping
      .precomposedStringWithCompatibilityMapping.lowercased()
    var out = ""
    for localCh in localCount.unicodeScalars {
      let localGc = localCh.properties.generalCategory
      // Python re.sub(r"[\s\W_]+", "") keeps only word chars minus underscore:
      // letters (L*) and numbers (N*). Everything else is dropped.
      if localGc == .uppercaseLetter || localGc == .lowercaseLetter || localGc == .titlecaseLetter
        || localGc == .modifierLetter || localGc == .otherLetter || localGc == .decimalNumber
        || localGc == .letterNumber || localGc == .otherNumber {
      } else {
        continue
      }
      out.unicodeScalars.append(localCh)
    }
    return out
  }
  static func normStrip(_ localString: String) -> String {
    var localToken = norm(localString)
    var changed = true
    while changed && localToken.count > 1 {
      changed = false
      for localPiece in particles {
        let localQueue = norm(localPiece)
        if localToken.hasSuffix(localQueue) && localToken.count - localQueue.count >= 1 {
          localToken = String(localToken.dropLast(localQueue.count))
          changed = true
          break
        }
      }
    }
    return localToken
  }
}

nonisolated public struct TermHint {
  public let text: String
  public let start: Int
  public let end: Int
  public let score: Float
}

nonisolated public enum TermHintDecoder {
  /// 내부 오프셋 공간은 unicodeScalar 인덱스(unit_offsets와 동일).
  /// Character(자소클러스터) 인덱스와 혼용하면 🇰🇷류 서로게이트/결합 문자에서
  /// 오프셋이 밀려 범위 밖 접근 크래시가 난다 — 모든 스팬 연산은 스칼라 공간으로 통일.
  static func sliceStr(_ localString: [Unicode.Scalar], _ localStart: Int, _ localEnd: Int)
    -> String {
    var localValue = String.UnicodeScalarView()
    localValue.append(contentsOf: localString[localStart..<localEnd])
    return String(localValue)
  }
  static func isL(_ localString: Unicode.Scalar) -> Bool {
    CharacterSet.letters.contains(localString)
  }
  static func isN(_ localString: Unicode.Scalar) -> Bool {
    switch localString.properties.generalCategory {
    case .decimalNumber, .letterNumber, .otherNumber: return true
    default: return false
    }
  }
  static func isW(_ localString: Unicode.Scalar) -> Bool { localString.properties.isWhitespace }

  static let innerParticles = [
    "이나", "거나", "또는", "및", "나", "와", "과", "의", "를", "을", "은", "는", "이", "가", "도", "만", "로", "으로",
    "에서", "까지", "부터"
  ]
  static let genPenalty: [String: Float] = [
    "pool": 1.0, "delim": 0.99, "word": 0.985, "ngram": 0.97, "ko_inner": 0.975, "charngram": 0.85,
    "ext": 0.97,
    "wsnap": 0.97, "piecejoin": 0.96, "dotsplit": 0.975, "duphalf": 0.96, "kospjoin": 0.85
  ]
  static let bridgeGap = 16  // 인접 풀 스팬 브리지 최대 문자 간격
  static let pieceMin: Float = 0.5  // piecejoin 조각 개별 평균확률 하한
  static let koCharngramHi = 10  // KO char-ngram 최대 길이
  static let defaultTau: [String: Float] = ["ko": 0.012, "en": 0.003]
  nonisolated(unsafe) public static var knownTerms: Set<String>?  // 사전 일치 후보 보너스 대상 (norm 표면)
  nonisolated(unsafe) public static var debugMerged = false
  nonisolated(unsafe) public static var lastMerged: [MergedCandidate] = []
  nonisolated(unsafe) public static var knownBonus: Float = 1.5
  static let cleanVarPenalty: Float = 0.94
  static let oligoScore: Float = 1.55
  static let noFilterKinds: Set<String> = ["duphalf", "cleanvar", "oligo"]
  static let oligoPattern: NSRegularExpression = {
    do {
      return try NSRegularExpression(
        pattern: "[35]'?-?[ACGTURYKMSWBDHVNacgturykmswbdhvn]{8,}-?[35]'?")
    } catch {
      preconditionFailure("Unable to compile oligo pattern: \(error)")
    }
  }()

  static let delimScalars = Set("()[\\]{},;:|/·•∙⋅<>=±~×→–—−-".unicodeScalars)
  static func isDelimiter(_ localCandidate: Unicode.Scalar) -> Bool {
    if localCandidate.value <= 0x1f { return true }
    return delimScalars.contains(localCandidate)
  }

  static func calcProbs(_ logits: [[Float]]) -> [Float] {
    logits.map { localLanguage in
      let localPieceKind = localLanguage.max() ?? 0
      let localExtra = localLanguage.map { exp($0 - localPieceKind) }
      let localString = localExtra.reduce(0, +)
      return (localExtra[1] + localExtra[2]) / localString
    }
  }

  static func viterbi(_ logits: [[Float]]) -> [Int] {
    if logits.isEmpty { return [] }
    let allowed: [[Int]] = [[0, 1, 2], [0, 1, 2], [1, 2]]
    var scores: [Float] = [-.infinity, -.infinity, -.infinity]
    var history: [[Int]] = []
    for (step, row) in logits.enumerated() {
      let peak = row.max() ?? 0
      let localEmbedding = row.map { $0 - peak }
      if step == 0 {
        scores = [localEmbedding[0], localEmbedding[1], -.infinity]
        continue
      }
      var parents = [0, 0, 0]
      var upd = [Float](repeating: 0, count: 3)
      for localLimit in 0..<3 {
        var best = allowed[localLimit][0]
        var bestv = scores[best]
        for localNextIndex in allowed[localLimit] where scores[localNextIndex] > bestv {
          bestv = scores[localNextIndex]
          best = localNextIndex
        }
        parents[localLimit] = best
        upd[localLimit] = scores[best] + localEmbedding[localLimit]
      }
      let localMaximum = upd.max() ?? 0
      scores = upd.map { $0 - localMaximum }
      history.append(parents)
    }
    var cur = 0
    if scores[1] > scores[cur] { cur = 1 }
    if scores[2] > scores[cur] { cur = 2 }
    var labels = [cur]
    for parents in history.reversed() {
      cur = parents[cur]
      labels.append(cur)
    }
    return labels.reversed()
  }

  static func words(_ text: [Unicode.Scalar], _ localStart: Int, _ localEnd: Int) -> [(Int, Int)] {
    var localWidth: [(Int, Int)] = []
    var localIndex = localStart
    while localIndex < localEnd {
      if isW(text[localIndex]) {
        localIndex += 1
        continue
      }
      var localNextIndex = localIndex
      while localNextIndex < localEnd && !isW(text[localNextIndex]) { localNextIndex += 1 }
      localWidth.append((localIndex, localNextIndex))
      localIndex = localNextIndex
    }
    return localWidth
  }
}
