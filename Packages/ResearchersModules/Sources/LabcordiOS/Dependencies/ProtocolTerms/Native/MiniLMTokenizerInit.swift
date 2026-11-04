import Foundation

nonisolated struct MiniLMTokenizerParts {
  let pieces: [String]
  let scores: [Double]
  let types: [Int]
  let charsmap: CharsMap
}

nonisolated struct MiniLMTokenizerStorage {
  let parts: MiniLMTokenizerParts
  let trie: [UInt8: MiniLMTokenizer.Node]
  let flatNodes: [MiniLMTokenizer.FlatNode]
  let flatEdges: [MiniLMTokenizer.FlatEdge]
  let compactMode: Bool
  let unkScore: Double
}

nonisolated extension MiniLMTokenizer {
  public init?(modelPath: String, compact: Bool? = nil) {
    let localCompact = compact ?? true
    guard let storage = Self.loadStorage(modelPath: modelPath, compact: localCompact) else {
      return nil
    }
    pieces = storage.parts.pieces
    scores = storage.parts.scores
    charsmap = storage.parts.charsmap
    trie = storage.trie
    flatNodes = storage.flatNodes
    flatEdges = storage.flatEdges
    compactMode = storage.compactMode
    unkScore = storage.unkScore
  }

  private static func loadStorage(
    modelPath: String, compact: Bool
  ) -> MiniLMTokenizerStorage? {
    guard let data = FileManager.default.contents(atPath: modelPath),
      let parts = parseModel(data) else { return nil }
    let idOf = makeID(parts.pieces)
    let unkScore =
      ((0..<parts.pieces.count).filter { parts.types[$0] == 1 }
        .map { parts.scores[$0] }.min() ?? 0) - 10.0
    if compact {
      guard let compactTrie = buildCompactTrie(parts, idOf: idOf) else { return nil }
      return MiniLMTokenizerStorage(
        parts: parts, trie: [:], flatNodes: compactTrie.nodes,
        flatEdges: compactTrie.edges, compactMode: true, unkScore: unkScore)
    }
    return MiniLMTokenizerStorage(
      parts: parts, trie: buildExpandedTrie(parts, idOf: idOf),
      flatNodes: [], flatEdges: [], compactMode: false, unkScore: unkScore)
  }

  private static func parseModel(_ data: Data) -> MiniLMTokenizerParts? {
    var localResult = ProtoReader(data)
    var pieces: [String] = []
    var scores: [Double] = []
    var types: [Int] = []
    var cmapBlob: [UInt8]?
    localResult.eachField { localField, _, localValue in
      if localField == 1, let piece = parsePiece(localValue) {
        pieces.append(piece.name)
        scores.append(piece.score)
        types.append(piece.type)
      } else if localField == 3 {
        cmapBlob = parseCharsMapBlob(localValue) ?? cmapBlob
      }
    }
    guard let blob = cmapBlob, let charsmap = CharsMap(blob: blob) else { return nil }
    return MiniLMTokenizerParts(pieces: pieces, scores: scores, types: types, charsmap: charsmap)
  }

  private static func parsePiece(_ value: Any) -> ParsedPiece? {
    guard let fieldBytes = value as? [UInt8] else { return nil }
    var localPrefix = ProtoReader(fieldBytes)
    var name = ""
    var localScore: Float = 0
    var localType = 1
    localPrefix.eachField { localField, _, localValue in
      if localField == 1, let bytes = localValue as? [UInt8],
        let decoded = String(bytes: bytes, encoding: .utf8) {
        name = decoded
      } else if localField == 2, let value = localValue as? Float {
        localScore = value
      } else if localField == 3, let value = localValue as? UInt64 {
        localType = Int(value)
      }
    }
    return ParsedPiece(name: name, score: Double(localScore), type: localType)
  }

  private static func parseCharsMapBlob(_ value: Any) -> [UInt8]? {
    guard let fieldBytes = value as? [UInt8] else { return nil }
    var localPrefix = ProtoReader(fieldBytes)
    var result: [UInt8]?
    localPrefix.eachField { localField, _, localValue in
      if localField == 2 { result = localValue as? [UInt8] }
    }
    return result
  }

  private static func makeID(_ pieces: [String]) -> [String: Int] {
    var id = [String: Int]()
    id.reserveCapacity(pieces.count + 8)
    let special = ["<s>": 0, "<pad>": 1, "</s>": 2, "<unk>": 3]
    for (localPiece, localString) in pieces.enumerated() {
      id[localString] = special[localString] ?? localPiece + 1
    }
    return id
  }

  private static func buildCompactTrie(
    _ parts: MiniLMTokenizerParts, idOf: [String: Int]
  ) -> (nodes: [FlatNode], edges: [FlatEdge])? {
    var nodes = [FlatNode()]
    var edges: [FlatEdge] = []
    nodes.reserveCapacity(800_000)
    edges.reserveCapacity(800_000)
    for (localPiece, piece) in parts.pieces.enumerated()
    where parts.types[localPiece] == 1 || parts.types[localPiece] == 2 {
      guard let localHFId = idOf[piece], localHFId <= Int(Int32.max) else { return nil }
      var localCount = 0
      for byte in piece.utf8 {
        var edge = nodes[localCount].firstEdge
        var found: Int?
        while edge >= 0 {
          let localEndValue = edges[Int(edge)]
          if localEndValue.byte == byte {
            found = Int(localEndValue.child)
            break
          }
          edge = localEndValue.next
        }
        if let value = found {
          localCount = value
        } else {
          guard nodes.count < Int(Int32.max), edges.count < Int(Int32.max) else { return nil }
          let child = nodes.count
          nodes.append(FlatNode())
          edges.append(
            FlatEdge(byte: byte, child: Int32(child), next: nodes[localCount].firstEdge))
          nodes[localCount].firstEdge = Int32(edges.count - 1)
          localCount = child
        }
      }
      nodes[localCount].leafID = Int32(localHFId)
      nodes[localCount].score = parts.scores[localPiece]
    }
    return (nodes, edges)
  }

  private static func buildExpandedTrie(
    _ parts: MiniLMTokenizerParts, idOf: [String: Int]
  ) -> [UInt8: Node] {
    let root = Node()
    for (localPiece, localString) in parts.pieces.enumerated()
    where parts.types[localPiece] == 1 || parts.types[localPiece] == 2 {
      guard let localHFId = idOf[localString] else { continue }
      var localCount = root
      for byte in localString.utf8 {
        if let localNextNode = localCount.child[byte] {
          localCount = localNextNode
        } else {
          let localInput = Node()
          localCount.child[byte] = localInput
          localCount = localInput
        }
      }
      localCount.leaf = (localHFId, parts.scores[localPiece])
    }
    return root.child
  }
}
