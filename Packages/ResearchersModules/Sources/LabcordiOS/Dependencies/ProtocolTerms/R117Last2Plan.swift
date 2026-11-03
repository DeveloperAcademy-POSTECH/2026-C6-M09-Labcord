import Foundation

/// 토큰 입력이 완전히 같은 후보만 묶고 후보별 pooling 위치는 유지합니다.
nonisolated struct R117Last2Plan: Sendable {
    struct Selection: Sendable {
        let candidate: Int
        let tokens: [Int]
    }

    struct Group: Sendable {
        let ids: [Int]
        var selections: [Selection]
    }

    let groups: [Group]

    init(text: String, spans: [Range<Int>], tokenizer: R117Tokenizer) throws {
        let scalars = Array(text.unicodeScalars)
        guard spans.allSatisfy({ $0.lowerBound >= 0 && $0.upperBound <= scalars.count
            && !$0.isEmpty }) else { throw R117RuntimeError.invalidCandidate }
        var groups: [Group] = []
        var positions: [[Int]: Int] = [:]
        for (candidate, range) in spans.enumerated() {
            try Task.checkCancellation()
            let input = try Self.input(scalars: scalars, range: range, tokenizer: tokenizer)
            let selection = Selection(candidate: candidate, tokens: input.tokens)
            if let position = positions[input.ids] {
                groups[position].selections.append(selection)
            } else {
                positions[input.ids] = groups.count
                groups.append(Group(ids: input.ids, selections: [selection]))
            }
        }
        self.groups = groups
    }

    private static func input(
        scalars: [UnicodeScalar], range: Range<Int>, tokenizer: R117Tokenizer
    ) throws -> (ids: [Int], tokens: [Int]) {
        let left = max(0, range.lowerBound - 160)
        let right = min(scalars.count, range.upperBound + 160)
        let normalized = scalars[left..<right].map { scalar -> UnicodeScalar in
            scalar.properties.generalCategory == .control
                && scalar != "\n" && scalar != "\r" && scalar != "\t" ? " " : scalar
        }
        let encoding = try tokenizer.encode(String(String.UnicodeScalarView(normalized)))
        let offsets = Array(encoding.offsets.prefix(510))
        let local = (range.lowerBound - left)..<(range.upperBound - left)
        for position in local where !normalized[position].properties.isWhitespace {
            if normalized[position].properties.generalCategory == .control { continue }
            guard offsets.contains(where: { $0.contains(position) }) else {
                throw R117RuntimeError.uncoveredSource
            }
        }
        let selected = offsets.indices.filter { offsets[$0].overlaps(local) }
        guard !selected.isEmpty else { throw R117RuntimeError.uncoveredSource }
        return ([0] + encoding.ids.prefix(510) + [2], selected.map { $0 + 1 })
    }
}
