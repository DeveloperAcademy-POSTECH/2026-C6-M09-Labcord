import Foundation

nonisolated struct MiniLMTokenizerParts {
  let pieces: [String]
  let scores: [Double]
  let types: [Int]
  let characterNormalizationMap: CharacterNormalizationMap
}

nonisolated struct MiniLMTokenizerStorage {
  let parts: MiniLMTokenizerParts
  let trie: [UInt8: MiniLMTokenizer.Node]
  let compactTrieNodes: [MiniLMTokenizer.CompactTrieNode]
  let compactTrieEdges: [MiniLMTokenizer.CompactTrieEdge]
  let usesCompactTrie: Bool
  let unknownTokenScore: Double
}

nonisolated extension MiniLMTokenizer {
  public init?(modelPath: String, compact: Bool? = nil) {
    let shouldUseCompactTrie = compact ?? true
    guard let storage = Self.loadStorage(
      modelPath: modelPath, compact: shouldUseCompactTrie) else {
      return nil
    }
    pieces = storage.parts.pieces
    scores = storage.parts.scores
    characterNormalizationMap = storage.parts.characterNormalizationMap
    trie = storage.trie
    compactTrieNodes = storage.compactTrieNodes
    compactTrieEdges = storage.compactTrieEdges
    usesCompactTrie = storage.usesCompactTrie
    unknownTokenScore = storage.unknownTokenScore
  }

  private static func loadStorage(
    modelPath: String, compact: Bool
  ) -> MiniLMTokenizerStorage? {
    guard let data = FileManager.default.contents(atPath: modelPath),
      let parts = parseModel(data) else { return nil }
    let tokenIDsByPiece = makeTokenIDsByPiece(parts.pieces)
    let unknownTokenScore =
      ((0..<parts.pieces.count).filter { parts.types[$0] == 1 }
        .map { parts.scores[$0] }.min() ?? 0) - 10.0
    if compact {
      guard let compactTrie = buildCompactTrie(parts, tokenIDsByPiece: tokenIDsByPiece) else {
        return nil
      }
      return MiniLMTokenizerStorage(
        parts: parts, trie: [:], compactTrieNodes: compactTrie.nodes,
        compactTrieEdges: compactTrie.edges, usesCompactTrie: true,
        unknownTokenScore: unknownTokenScore)
    }
    return MiniLMTokenizerStorage(
      parts: parts, trie: buildExpandedTrie(parts, tokenIDsByPiece: tokenIDsByPiece),
      compactTrieNodes: [], compactTrieEdges: [], usesCompactTrie: false,
      unknownTokenScore: unknownTokenScore)
  }

  private static func parseModel(_ data: Data) -> MiniLMTokenizerParts? {
    var modelReader = ProtobufReader(data)
    var pieces: [String] = []
    var scores: [Double] = []
    var types: [Int] = []
    var normalizationMapData: [UInt8]?
    modelReader.forEachField { fieldNumber, _, fieldValue in
      if fieldNumber == 1, let piece = parsePiece(fieldValue) {
        pieces.append(piece.name)
        scores.append(piece.score)
        types.append(piece.type)
      } else if fieldNumber == 3 {
        normalizationMapData = parseNormalizationMapData(fieldValue) ?? normalizationMapData
      }
    }
    guard let blob = normalizationMapData,
      let characterNormalizationMap = CharacterNormalizationMap(blob: blob) else { return nil }
    return MiniLMTokenizerParts(
      pieces: pieces, scores: scores, types: types,
      characterNormalizationMap: characterNormalizationMap)
  }

  private static func parsePiece(_ value: Any) -> ParsedPiece? {
    guard let fieldBytes = value as? [UInt8] else { return nil }
    var fieldReader = ProtobufReader(fieldBytes)
    var name = ""
    var pieceScore: Float = 0
    var pieceType = 1
    fieldReader.forEachField { fieldNumber, _, fieldValue in
      if fieldNumber == 1, let bytes = fieldValue as? [UInt8],
        let decoded = String(bytes: bytes, encoding: .utf8) {
        name = decoded
      } else if fieldNumber == 2, let value = fieldValue as? Float {
        pieceScore = value
      } else if fieldNumber == 3, let value = fieldValue as? UInt64 {
        pieceType = Int(value)
      }
    }
    return ParsedPiece(name: name, score: Double(pieceScore), type: pieceType)
  }

  private static func parseNormalizationMapData(_ value: Any) -> [UInt8]? {
    guard let fieldBytes = value as? [UInt8] else { return nil }
    var fieldReader = ProtobufReader(fieldBytes)
    var result: [UInt8]?
    fieldReader.forEachField { fieldNumber, _, fieldValue in
      if fieldNumber == 2 { result = fieldValue as? [UInt8] }
    }
    return result
  }

  private static func makeTokenIDsByPiece(_ pieces: [String]) -> [String: Int] {
    var id = [String: Int]()
    id.reserveCapacity(pieces.count + 8)
    let special = ["<s>": 0, "<pad>": 1, "</s>": 2, "<unk>": 3]
    for (pieceIndex, pieceText) in pieces.enumerated() {
      id[pieceText] = special[pieceText] ?? pieceIndex + 1
    }
    return id
  }

  private static func buildCompactTrie(
    _ parts: MiniLMTokenizerParts, tokenIDsByPiece: [String: Int]
  ) -> (nodes: [CompactTrieNode], edges: [CompactTrieEdge])? {
    var nodes = [CompactTrieNode()]
    var edges: [CompactTrieEdge] = []
    nodes.reserveCapacity(800_000)
    edges.reserveCapacity(800_000)
    for (pieceIndex, piece) in parts.pieces.enumerated()
    where parts.types[pieceIndex] == 1 || parts.types[pieceIndex] == 2 {
      guard let tokenID = tokenIDsByPiece[piece], tokenID <= Int(Int32.max) else { return nil }
      var currentNode = 0
      for byte in piece.utf8 {
        var edge = nodes[currentNode].firstEdge
        var found: Int?
        while edge >= 0 {
          let edgeValue = edges[Int(edge)]
          if edgeValue.byte == byte {
            found = Int(edgeValue.child)
            break
          }
          edge = edgeValue.next
        }
        if let value = found {
          currentNode = value
        } else {
          guard nodes.count < Int(Int32.max), edges.count < Int(Int32.max) else { return nil }
          let child = nodes.count
          nodes.append(CompactTrieNode())
          edges.append(
            CompactTrieEdge(byte: byte, child: Int32(child), next: nodes[currentNode].firstEdge))
          nodes[currentNode].firstEdge = Int32(edges.count - 1)
          currentNode = child
        }
      }
      nodes[currentNode].tokenID = Int32(tokenID)
      nodes[currentNode].score = parts.scores[pieceIndex]
    }
    return (nodes, edges)
  }

  private static func buildExpandedTrie(
    _ parts: MiniLMTokenizerParts, tokenIDsByPiece: [String: Int]
  ) -> [UInt8: Node] {
    let root = Node()
    for (pieceIndex, pieceText) in parts.pieces.enumerated()
    where parts.types[pieceIndex] == 1 || parts.types[pieceIndex] == 2 {
      guard let tokenID = tokenIDsByPiece[pieceText] else { continue }
      var currentNode = root
      for byte in pieceText.utf8 {
        if let nextNode = currentNode.child[byte] {
          currentNode = nextNode
        } else {
          let newNode = Node()
          currentNode.child[byte] = newNode
          currentNode = newNode
        }
      }
      currentNode.leaf = (tokenID, parts.scores[pieceIndex])
    }
    return root.child
  }
}
