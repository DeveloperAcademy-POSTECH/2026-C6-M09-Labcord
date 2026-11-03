import Foundation

/// 모든 원문 언급이 같은 농도 완전형에 연결될 때만 표면을 복원합니다.
nonisolated enum ProtocolTermSourceCompletion {
    static func complete(_ terms: [String], source: String, blocks: [Range<Int>]) -> [String] {
        let context = TermCompletionSource(source: source, blocks: blocks)
        var result = terms
        for (index, term) in terms.enumerated() {
            guard let completed = context.completion(of: term),
                  !terms.contains(completed), !result.contains(completed) else { continue }
            result[index] = completed
        }
        return result
    }
}

nonisolated private struct TermCompletionSource {
    private static let word = #"[\p{L}\p{M}\p{N}_]"#
    private static let units = #"(?:%|mM|µM|μM|uM|M|mg/mL|mg/L|g/L|g/mL|mol/L|mmol/L)"#
    let source: String
    let blocks: [Range<Int>]

    init(source: String, blocks: [Range<Int>]) {
        self.source = source
        let count = source.unicodeScalars.count
        self.blocks = blocks.filter { $0.lowerBound >= 0 && $0.upperBound <= count }
    }

    func completion(of term: String) -> String? {
        guard !term.isEmpty, !term.contains(where: { "()[]{}".contains($0) }) else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: term)
        let boundary = "(?<!\(Self.word))" + escaped + "(?!\(Self.word))"
        let mentions = matches(boundary)
        guard !mentions.isEmpty else { return nil }
        let pattern = boundary + #"[ \t]*\([0-9]+(?:\.[0-9]+)?\s*"#
            + Self.units + #"\)"#
        let completions = matches(pattern).filter { validCompletion($0.range) }
        guard completions.count == mentions.count,
              let first = completions.first,
              let firstRange = Range(first.range, in: source) else { return nil }
        let completed = String(source[firstRange])
        guard completions.allSatisfy({ match in
            Range(match.range, in: source).map { String(source[$0]) == completed } ?? false
        }), mentions.allSatisfy({ mention in
            completions.contains { completion in
                completion.range.location <= mention.range.location
                    && NSMaxRange(mention.range) <= NSMaxRange(completion.range)
            }
        }) else { return nil }
        return completed
    }

    private func matches(_ pattern: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
    }

    private func validCompletion(_ match: NSRange) -> Bool {
        guard let range = Range(match, in: source),
              let lower = range.lowerBound.samePosition(in: source.unicodeScalars),
              let upper = range.upperBound.samePosition(in: source.unicodeScalars) else {
            return false
        }
        if range.upperBound < source.endIndex, source[range.upperBound] == ")" { return false }
        let scalars = source.unicodeScalars
        let start = scalars.distance(from: scalars.startIndex, to: lower)
        let end = scalars.distance(from: scalars.startIndex, to: upper)
        let span = start..<end
        return blocks.contains { $0.lowerBound <= span.lowerBound
            && span.upperBound <= $0.upperBound }
    }
}
