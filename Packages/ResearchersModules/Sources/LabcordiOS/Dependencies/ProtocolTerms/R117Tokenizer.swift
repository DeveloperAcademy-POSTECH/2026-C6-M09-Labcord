import Foundation

/// JSON에 고정된 Unigram 어휘와 정규화 표를 사용합니다. 좌표는 Unicode scalar입니다.
nonisolated final class R117Tokenizer {
    struct Encoding: Sendable {
        var ids: [Int]
        var offsets: [Range<Int>]
    }

    private final class Node {
        var children: [UInt8: Node] = [:]
        var token: (id: Int, score: Double)?
    }

    private let root = Node()
    private let characters: CharsMap
    private let unknownScore: Double
    private let specialTokens: [R117AddedToken]

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? [String: Any],
              model["type"] as? String == "Unigram",
              let vocabulary = model["vocab"] as? [[Any]],
              let normalization = json["normalizer"] as? [String: Any],
              let sequence = normalization["normalizers"] as? [[String: Any]],
              let encoded = sequence.first?["precompiled_charsmap"] as? String,
              let blob = Data(base64Encoded: encoded),
              let characters = CharsMap(blob: Array(blob)) else {
            throw R117RuntimeError.invalidTokenizer
        }
        self.characters = characters
        var minimum = Double.infinity
        for (id, entry) in vocabulary.enumerated() {
            guard let piece = entry.first as? String, let score = entry.last as? Double else {
                throw R117RuntimeError.invalidTokenizer
            }
            minimum = min(minimum, score)
            var node = root
            for byte in piece.utf8 {
                if node.children[byte] == nil { node.children[byte] = Node() }
                guard let next = node.children[byte] else {
                    throw R117RuntimeError.invalidTokenizer
                }
                node = next
            }
            node.token = (id, score)
        }
        unknownScore = minimum - 10
        let added = json["added_tokens"] as? [[String: Any]] ?? []
        specialTokens = added.compactMap { entry in
            guard let text = entry["content"] as? String, let id = entry["id"] as? Int else {
                return nil
            }
            return R117AddedToken(
                content: text, id: id, leftStrip: entry["lstrip"] as? Bool ?? false,
                rightStrip: entry["rstrip"] as? Bool ?? false
            )
        }.sorted { $0.content.count > $1.content.count }
    }

    func encode(_ text: String) throws -> Encoding {
        let scalars = Array(text.unicodeScalars)
        var result = Encoding(ids: [], offsets: [])
        var beginning = 0
        var position = 0
        while position < scalars.count {
            guard scalars[position] == "<" else {
                position += 1
                continue
            }
            if let match = specialMatch(in: scalars, at: position, lowerBound: beginning) {
                appendNormal(Array(scalars[beginning..<match.range.lowerBound]),
                             base: beginning, to: &result)
                result.ids.append(match.id)
                result.offsets.append(match.range)
                position = match.range.upperBound
                beginning = position
            } else {
                position += 1
            }
        }
        appendNormal(Array(scalars[beginning...]), base: beginning, to: &result)
        guard result.ids.count == result.offsets.count else {
            throw R117RuntimeError.invalidTokenizer
        }
        return result
    }

    private func specialMatch(
        in scalars: [UnicodeScalar], at position: Int, lowerBound: Int
    ) -> (id: Int, range: Range<Int>)? {
        for special in specialTokens {
            if let range = special.matchedRange(
                in: scalars, at: position, lowerBound: lowerBound
            ) {
                return (special.id, range)
            }
        }
        return nil
    }

    private func appendNormal(
        _ source: [UnicodeScalar], base: Int, to result: inout Encoding
    ) {
        guard !source.isEmpty else { return }
        var bytes: [UInt8] = []
        var locations: [Int] = []
        for (index, scalar) in source.enumerated() {
            let value = scalar.properties.generalCategory == .control
                && !scalar.properties.isWhitespace ? " " : String(scalar)
            let encoded = Array(value.utf8)
            bytes += encoded
            locations += Array(repeating: base + index, count: encoded.count)
        }
        let normalized = normalize(bytes: bytes, locations: locations)
        split(normalized, to: &result)
    }

    private func normalize(
        bytes: [UInt8], locations: [Int]
    ) -> [(UnicodeScalar, Range<Int>)] {
        var normalized: [(UnicodeScalar, Range<Int>)] = []
        var position = 0
        while position < bytes.count {
            let match = characters.commonPrefix(bytes[position...]).last
            let length: Int
            let replacement: [UInt8]
            if let match {
                length = match.0
                replacement = Array(characters.replacement(at: match.1))
            } else {
                let first = bytes[position]
                length = first < 0x80 ? 1 : (first < 0xE0 ? 2 : (first < 0xF0 ? 3 : 4))
                replacement = Array(bytes[position..<min(bytes.count, position + length)])
            }
            let end = min(bytes.count, position + length)
            let range = locations[position]..<(locations[end - 1] + 1)
            for scalar in (String(bytes: replacement, encoding: .utf8) ?? "").unicodeScalars {
                normalized.append((scalar, range))
            }
            position = end
        }
        return normalized
    }

    private func split(
        _ input: [(UnicodeScalar, Range<Int>)], to result: inout Encoding
    ) {
        var normalized = input
        while normalized.last?.0.properties.isWhitespace == true { normalized.removeLast() }
        var replaced: [(UnicodeScalar, Range<Int>)] = []
        var position = 0
        while position < normalized.count {
            var end = position + 1
            if normalized[position].0 == " " {
                while end < normalized.count, normalized[end].0 == " " { end += 1 }
            }
            let range = normalized[position].1.lowerBound..<normalized[end - 1].1.upperBound
            let scalar: UnicodeScalar = normalized[position].0 == " "
                ? "▁" : normalized[position].0
            replaced.append((scalar, range))
            position = end
        }
        guard let first = replaced.first else { return }
        if first.0 != "▁" { replaced.insert(("▁", first.1), at: 0) }
        var start = 0
        for index in 1...replaced.count where index == replaced.count || replaced[index].0 == "▁" {
            appendPiece(Array(replaced[start..<index]), to: &result)
            start = index
        }
    }

    private func appendPiece(
        _ piece: [(UnicodeScalar, Range<Int>)], to result: inout Encoding
    ) {
        var bytes: [UInt8] = []
        var mapping: [Range<Int>] = []
        var boundaries: [Int] = []
        for (scalar, range) in piece {
            boundaries.append(bytes.count)
            let encoded = Array(String(scalar).utf8)
            bytes += encoded
            mapping += Array(repeating: range, count: encoded.count)
        }
        boundaries.append(bytes.count)
        var scores = Array(repeating: -Double.infinity, count: bytes.count + 1)
        var back = Array(repeating: (start: 0, id: 3), count: bytes.count + 1)
        scores[0] = 0
        for index in 0..<boundaries.count - 1 {
            let start = boundaries[index]
            var node = root
            var end = start
            var single = false
            while end < bytes.count, let next = node.children[bytes[end]] {
                node = next
                end += 1
                if let token = node.token {
                    let score = scores[start] + token.score
                    if score > scores[end] {
                        scores[end] = score
                        back[end] = (start, token.id)
                    }
                    if end == boundaries[index + 1] { single = true }
                }
            }
            if !single, scores[start] + unknownScore > scores[boundaries[index + 1]] {
                let end = boundaries[index + 1]
                scores[end] = scores[start] + unknownScore
                back[end] = (start, 3)
            }
        }
        appendTokens(bytes: bytes, mapping: mapping, back: back, to: &result)
    }

    private func appendTokens(
        bytes: [UInt8], mapping: [Range<Int>], back: [(start: Int, id: Int)],
        to result: inout Encoding
    ) {
        var tokens: [(Int, Range<Int>)] = []
        var end = bytes.count
        while end > 0 {
            let previous = back[end]
            let range = mapping[previous.start].lowerBound..<mapping[end - 1].upperBound
            tokens.append((previous.id, range))
            end = previous.start
        }
        var previousWasUnknown = false
        for (id, range) in tokens.reversed() {
            if id == 3, previousWasUnknown, let previous = result.offsets.last {
                result.offsets[result.offsets.count - 1] = previous.lowerBound..<range.upperBound
            } else {
                result.ids.append(id)
                result.offsets.append(range)
            }
            previousWasUnknown = id == 3
        }
    }
}

/// AddedToken의 strip 범위도 원문 좌표에 포함합니다. 일반 토큰 정규화보다 먼저 적용합니다.
nonisolated struct R117AddedToken {
    let content: String
    let id: Int
    let leftStrip: Bool
    let rightStrip: Bool

    func matchedRange(
        in source: [UnicodeScalar], at position: Int, lowerBound: Int
    ) -> Range<Int>? {
        let token = Array(content.unicodeScalars)
        guard !token.isEmpty, lowerBound >= 0, position >= lowerBound,
              position + token.count <= source.count,
              source[position..<(position + token.count)].elementsEqual(token) else { return nil }
        var start = position
        var end = position + token.count
        if leftStrip {
            while start > lowerBound, source[start - 1].properties.isWhitespace { start -= 1 }
        }
        if rightStrip {
            while end < source.count, source[end].properties.isWhitespace { end += 1 }
        }
        return start..<end
    }
}

nonisolated enum R117RuntimeError: Error {
    case invalidTokenizer
    case invalidModelOutput
    case uncoveredSource
    case invalidCandidate
}
