import Foundation
import OmniParser

/// 원문 scalar 좌표와 파서 블록을 대조해 서로 다른 요소를 잇는 후보를 제거합니다.
nonisolated enum ProtocolDocumentTermCleaner {
    enum Error: Swift.Error { case inconsistentDocument }

    private struct Candidate {
        let text: String
        let ranges: [Range<Int>]
    }

    static func clean(_ terms: [String], document: DocumentParseResult) throws -> [String] {
        try Task.checkCancellation()
        let ranges = blockRanges(document)
        guard ranges.text == document.fullText else { throw Error.inconsistentDocument }
        let source = document.fullText
        let scalars = Array(source.unicodeScalars)
        let restored = ProtocolTermSourceCompletion.complete(
            terms, source: source, blocks: ranges.blocks
        )
        try Task.checkCancellation()
        let surfaces = restored.flatMap { term -> [String] in
            let isContained = occurrences(of: term, in: source).contains { occurrence in
                ranges.blocks.contains { $0.lowerBound <= occurrence.lowerBound
                    && occurrence.upperBound <= $0.upperBound }
            }
            guard isContained, !crossesListItem(term), !crossesReactions(term) else { return [] }
            let repaired = DocumentTermSurfaceRepair.repair(
                term, source: source, blocks: ranges.blocks
            )
            return splitList(repaired)
        }
        let candidates: [Candidate] = surfaces.compactMap { surface in
            guard !surface.isEmpty, !isTruncatedSymbol(surface),
                  !DocumentTermSurfaceRepair.isOrphanedPercent(surface),
                  hasBalancedDelimiters(surface) else { return nil }
            let valid = occurrences(of: surface, in: source).filter { occurrence in
                ranges.blocks.contains { $0.lowerBound <= occurrence.lowerBound
                    && occurrence.upperBound <= $0.upperBound }
            }
            guard !valid.isEmpty else { return nil }
            return Candidate(text: surface, ranges: valid)
        }
        let complete = candidates.filter { !isBrokenKoreanEnding($0, source: source) }
        let expanded = complete.map { candidate in
            expandComposite(candidate, source: source, blocks: ranges.blocks)
        }
        let canonical = expanded.filter { !isInflected($0, candidates: expanded) }
        var seen = Set<String>()
        let result = Array(canonical.filter { candidate in
            guard seen.insert(candidate.text).inserted else { return false }
            return !candidate.ranges.allSatisfy { range in
                isFragment(range, scalars: scalars) && canonical.contains { other in
                    other.text != candidate.text && other.ranges.contains {
                        $0.lowerBound <= range.lowerBound && $0.upperBound >= range.upperBound
                    }
                }
            }
        }.map(\.text).prefix(50))
        try Task.checkCancellation()
        return result
    }

    private static func expandComposite(
        _ candidate: Candidate, source: String, blocks: [Range<Int>]
    ) -> Candidate {
        guard candidate.text.contains("_") else { return candidate }
        let pattern = "[\\p{L}\\p{N}]+\\([^()\\n]*_[^()\\n]*\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return candidate }
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        let enclosing: [(String, Range<Int>)] = matches.compactMap { match in
            guard let range = Range(match.range, in: source),
                  let start = range.lowerBound.samePosition(in: source.unicodeScalars),
                  let end = range.upperBound.samePosition(in: source.unicodeScalars) else {
                return nil
            }
            let scalarRange = source.unicodeScalars.distance(
                from: source.unicodeScalars.startIndex, to: start
            )..<source.unicodeScalars.distance(from: source.unicodeScalars.startIndex, to: end)
            guard blocks.contains(where: { $0.lowerBound <= scalarRange.lowerBound
                && scalarRange.upperBound <= $0.upperBound }) else { return nil }
            return (String(source[range]), scalarRange)
        }
        let expansions = candidate.ranges.map { range -> String? in
            let valid = enclosing.filter { $0.1.lowerBound < range.lowerBound
                && $0.1.upperBound > range.upperBound }
            guard valid.count == 1 else { return nil }
            return valid[0].0
        }
        guard let first = expansions.first ?? nil,
              expansions.allSatisfy({ $0 == first }) else { return candidate }
        return Candidate(text: first, ranges: occurrences(of: first, in: source))
    }

    private static func splitList(_ text: String) -> [String] {
        var parts: [String] = []
        var start = text.startIndex
        let pairs: [Character: Character] = [")": "(", "）": "（", "]": "[", "}": "{"]
        let opening = Set(pairs.values)
        var stack: [Character] = []
        for index in text.indices {
            let character = text[index]
            if opening.contains(character) { stack.append(character) }
            if let expected = pairs[character], stack.last == expected { stack.removeLast() }
            guard stack.isEmpty, character == ";" || character == "," else { continue }
            if character == "," && isChemicalComma(text, at: index) { continue }
            let piece = text[start..<index].trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { parts.append(piece) }
            start = text.index(after: index)
        }
        let piece = text[start...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !piece.isEmpty { parts.append(piece) }
        return parts
    }

    private static func isChemicalComma(_ text: String, at index: String.Index) -> Bool {
        let left = String(text[..<index])
        let right = String(text[text.index(after: index)...])
        let locantLeft = left.range(of: "(?:^|[^A-Za-z0-9])[0-9]+$|(?:^|[^A-Za-z])N$",
                                    options: .regularExpression) != nil
        let locantRight = right.range(of: "^\\s*(?:[0-9]+|N)\\s*[-,]",
                                      options: .regularExpression) != nil
        return locantLeft && locantRight
    }

    private static func crossesReactions(_ term: String) -> Bool {
        let lines = term.components(separatedBy: .newlines)
        return lines.filter { $0.contains("→") || $0.contains("->") || $0.contains("⇌") }.count > 1
    }

    private static func blockRanges(
        _ document: DocumentParseResult
    ) -> (text: String, blocks: [Range<Int>]) {
        var text = ""
        var blocks: [Range<Int>] = []
        var offset = 0
        for block in document.blocks where !block.text.isEmpty
                && block.kind != .table && block.kind != .image {
            if !text.isEmpty { text.append("\n"); offset += 1 }
            let length = block.text.unicodeScalars.count
            blocks.append(offset..<(offset + length))
            text.append(block.text)
            offset += length
        }
        return (text, blocks)
    }

    private static func occurrences(of term: String, in source: String) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var offset = source.startIndex
        while offset < source.endIndex,
              let range = source.range(of: term, range: offset..<source.endIndex) {
            let scalars = source.unicodeScalars
            guard let left = range.lowerBound.samePosition(in: scalars),
                  let right = range.upperBound.samePosition(in: scalars) else { break }
            let start = scalars.distance(from: scalars.startIndex, to: left)
            let end = scalars.distance(from: scalars.startIndex, to: right)
            result.append(start..<end)
            offset = source.index(after: range.lowerBound)
        }
        return result
    }

    private static func isFragment(_ range: Range<Int>, scalars: [Unicode.Scalar]) -> Bool {
        func isWord(_ scalar: Unicode.Scalar) -> Bool {
            CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
        }
        let beginsWithParenthesis = scalars[range.lowerBound] == "("
            || scalars[range.lowerBound] == "（"
        return (range.lowerBound > 0 && isWord(scalars[range.lowerBound - 1])
                && (isWord(scalars[range.lowerBound]) || beginsWithParenthesis))
            || (range.upperBound < scalars.count && isWord(scalars[range.upperBound - 1])
                && isWord(scalars[range.upperBound]))
    }

    private static func isInflected(_ candidate: Candidate, candidates: [Candidate]) -> Bool {
        let particles = ["은", "는", "이", "가", "을", "를", "의", "에", "에서", "으로", "로"]
        return candidates.contains { other in
            other.text != candidate.text && other.text.count >= 2
                && particles.contains { candidate.text == other.text + $0 }
        }
    }

    private static func isBrokenKoreanEnding(_ candidate: Candidate, source: String) -> Bool {
        let words = candidate.text.split { $0.isWhitespace }
        guard words.count > 1, let last = words.last, last.count == 1,
              let value = last.unicodeScalars.first, (0xAC00...0xD7A3).contains(value.value)
        else { return false }
        let scalars = Array(source.unicodeScalars)
        let particles = ["은", "는", "이", "가", "을", "를", "의", "에", "에서", "으로", "로"]
        return candidate.ranges.allSatisfy { range in
            let suffix = scalars[range.upperBound...].prefix {
                (0xAC00...0xD7A3).contains($0.value)
            }
            let text = String(String.UnicodeScalarView(suffix))
            return !text.isEmpty && !particles.contains(text)
        }
    }

    private static func hasBalancedDelimiters(_ text: String) -> Bool {
        let pairs: [Character: Character] = [")": "(", "）": "（", "]": "[", "}": "{"]
        let opening = Set(pairs.values)
        var stack: [Character] = []
        for character in text {
            if opening.contains(character) {
                stack.append(character)
            } else if let expected = pairs[character], stack.popLast() != expected {
                return false
            }
        }
        return stack.isEmpty
    }

    private static func isTruncatedSymbol(_ term: String) -> Bool {
        term.range(of: "^[A-Za-z]\\.$|^[A-Za-z]{1,3}\\?$", options: .regularExpression) != nil
    }

    private static func crossesListItem(_ term: String) -> Bool {
        term.range(of: "\\n\\s*(?:[0-9]+[.)]|[-•])\\s", options: .regularExpression) != nil
    }
}

/// 새 이름을 생성하지 않고, 같은 블록의 모든 출현에서 완전한 표기가 일치할 때만 복원합니다.
nonisolated private enum DocumentTermSurfaceRepair {
    private static let delimiterPattern = """
        [\\p{L}\\p{N}]+[（(][^()（）\\n]{1,80}[)）][\\p{L}\\p{N}]*|\
        \\[[^\\[\\]\\n]{1,80}\\][\\p{L}\\p{N}]*
        """

    static func repair(_ term: String, source: String, blocks: [Range<Int>]) -> String {
        let valid = occurrences(of: term, in: source).filter { occurrence in
            blocks.contains { $0.lowerBound <= occurrence.lowerBound
                && occurrence.upperBound <= $0.upperBound }
        }
        guard !valid.isEmpty else { return term }
        let completions: [String?]
        if isOrphanedPercent(term) {
            completions = valid.map { completeConcentration($0, source: source) }
        } else if needsDelimiterRepair(term) {
            completions = delimiterCompletions(valid, source: source, blocks: blocks)
        } else {
            return term
        }
        guard let first = completions.first ?? nil,
              completions.allSatisfy({ $0 == first }) else { return term }
        return first
    }

    static func isOrphanedPercent(_ term: String) -> Bool {
        let normalized = term.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix("%"), normalized.count > 1 else { return false }
        let unit = "^%\\s*(?:R\\.?H\\.?|\\(?[vw]/[vw]\\)?)$"
        return normalized.range(of: unit, options: [.regularExpression, .caseInsensitive]) == nil
    }

    private static func needsDelimiterRepair(_ term: String) -> Bool {
        let pairs: [Character: Character] = [")": "(", "）": "（", "]": "["]
        let opening = Set(pairs.values)
        if let first = term.first, opening.contains(first) { return true }
        var stack: [Character] = []
        for character in term {
            if opening.contains(character) { stack.append(character) }
            if let expected = pairs[character], stack.popLast() != expected { return true }
        }
        return !stack.isEmpty
    }

    private static func delimiterCompletions(
        _ occurrences: [Range<Int>], source: String, blocks: [Range<Int>]
    ) -> [String?] {
        guard let regex = try? NSRegularExpression(pattern: delimiterPattern) else { return [] }
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        let enclosing = matches.compactMap { match -> (String, Range<Int>)? in
            guard let range = Range(match.range, in: source),
                  let scalarRange = scalarRange(range, in: source),
                  blocks.contains(where: { $0.lowerBound <= scalarRange.lowerBound
                      && scalarRange.upperBound <= $0.upperBound }) else { return nil }
            return (String(source[range]), scalarRange)
        }
        return occurrences.map { occurrence in
            let valid = enclosing.filter { $0.1.lowerBound <= occurrence.lowerBound
                && occurrence.upperBound <= $0.1.upperBound }
            return valid.count == 1 ? valid[0].0 : nil
        }
    }

    private static func completeConcentration(_ range: Range<Int>, source: String) -> String? {
        let scalars = Array(source.unicodeScalars)
        var left = range.lowerBound
        while left > 0, scalars[left - 1] == " " { left -= 1 }
        let end = left
        while left > 0, "0123456789.,".unicodeScalars.contains(scalars[left - 1]) { left -= 1 }
        guard left < end else { return nil }
        let number = String(String.UnicodeScalarView(scalars[left..<end]))
        guard number.range(of: "^[0-9]+(?:[.,][0-9]+)?$", options: .regularExpression) != nil,
              left == 0 || !CharacterSet.alphanumerics.contains(scalars[left - 1]) else {
            return nil
        }
        return String(String.UnicodeScalarView(scalars[left..<range.upperBound]))
    }

    private static func occurrences(of term: String, in source: String) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var offset = source.startIndex
        while offset < source.endIndex,
              let range = source.range(of: term, range: offset..<source.endIndex) {
            guard let scalars = scalarRange(range, in: source) else { break }
            result.append(scalars)
            offset = source.index(after: range.lowerBound)
        }
        return result
    }

    private static func scalarRange(
        _ range: Range<String.Index>, in source: String
    ) -> Range<Int>? {
        let scalars = source.unicodeScalars
        guard let left = range.lowerBound.samePosition(in: scalars),
              let right = range.upperBound.samePosition(in: scalars) else { return nil }
        let start = scalars.distance(from: scalars.startIndex, to: left)
        let end = scalars.distance(from: scalars.startIndex, to: right)
        return start..<end
    }
}
