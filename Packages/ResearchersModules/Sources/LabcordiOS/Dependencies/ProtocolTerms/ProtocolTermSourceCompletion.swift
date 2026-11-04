import Foundation
import OmniParser

nonisolated enum ProtocolTermSourceCompletion {
    static func isExplicitConcentration(
        surface: String, range: Range<Int>, source: String
    ) -> Bool {
        let concentrationPattern = #"[0-9]+(?:\.[0-9]+)?[ ]*"#
            + TermCompletionSourceContext.concentrationUnitPattern
        let context = TermCompletionSourceContext(
            source: source, blocks: [0..<source.unicodeScalars.count])
        guard surface.range(of: concentrationPattern, options: .regularExpression) != nil,
              context.isSupportedSurface(
                surface, concentrationPattern: concentrationPattern, concentrationOnly: true),
              range.lowerBound >= 0, range.upperBound <= source.unicodeScalars.count,
              !range.isEmpty else { return false }
        let sourceScalars = source.unicodeScalars
        let scalarStartIndex = sourceScalars.index(
            sourceScalars.startIndex, offsetBy: range.lowerBound)
        let scalarEndIndex = sourceScalars.index(scalarStartIndex, offsetBy: range.count)
        guard Array(sourceScalars[scalarStartIndex..<scalarEndIndex])
            == Array(surface.unicodeScalars) else { return false }
        guard context.isContainedCompletion(
            NSRange(scalarStartIndex..<scalarEndIndex, in: source)) else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: surface)
        let pattern = "(?<![\\p{L}\\p{M}\\p{N}_])" + escaped
            + "(?![\\p{L}\\p{M}\\p{N}_])"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              regex.firstMatch(in: source, options: .withTransparentBounds,
                range: NSRange(scalarStartIndex..<scalarEndIndex, in: source)) != nil
        else { return false }
        let end = sourceScalars[scalarEndIndex...].firstIndex(of: "\n") ?? sourceScalars.endIndex
        let sameLineSourceContext = TermCompletionSourceContext(
            source: source, blocks: [0..<sourceScalars.distance(
            from: sourceScalars.startIndex, to: end)])
        let lineHead = String(source[..<scalarStartIndex].reversed()
            .prefix { !$0.isNewline }.reversed())
        return sameLineSourceContext.hasUnambiguousQuantityContext(
            scalarStartIndex..<scalarEndIndex,
            concentrationPattern: concentrationPattern, quantityHead: lineHead)
    }

    static func reviewRow(
        original: String, proposed: String, category: ProtocolTermReviewCategory,
        document: DocumentParseResult
    ) -> ProtocolTermReviewRow? {
        let preservesOriginalSurface = Array(original.unicodeScalars)
            == Array(proposed.unicodeScalars)
        let spans = ProtocolDocumentTermCleaner.sourceSpans(document) ?? []
        let context = TermCompletionSourceContext(
            source: document.fullText, blocks: spans.map { $0.start..<$0.end }
        )
        let range = preservesOriginalSurface ? context.exactMentionRanges(original)
            .first { range in
            spans.contains { $0.start <= range.lowerBound && range.upperBound <= $0.end }
        } : context.completionEvidenceRange(original: original, proposed: proposed)
        let evidence = range.flatMap { range in
            spans.first { $0.start <= range.lowerBound && range.upperBound <= $0.end }.map {
                ProtocolTermSourceSpan(
                    start: range.lowerBound, end: range.upperBound, blockIndex: $0.blockIndex
                )
            }
        }
        guard preservesOriginalSurface || evidence != nil else { return nil }
        return ProtocolTermReviewRow(
            original: original, surface: proposed, category: category, evidence: evidence
        )
    }

    static func supportedReviewSurfaces(
        original: String, document: DocumentParseResult
    ) -> [String] {
        guard !original.isEmpty, let spans = ProtocolDocumentTermCleaner.sourceSpans(document),
              !spans.contains(where: {
                  $0.end - $0.start > 4_000 && document.blocks[$0.blockIndex].text.range(
                      of: original, options: .literal
                  ) != nil
              }) else { return [original] }
        let context = TermCompletionSourceContext(
            source: document.fullText, blocks: spans.map { $0.start..<$0.end }
        )
        var surfaces = [original]
        var seen = Set([Data(original.utf8)])
        for (surface, _) in context.supportedCompletionCandidates(original: original) {
            guard seen.insert(Data(surface.utf8)).inserted,
                  reviewRow(original: original, proposed: surface, category: .glossary,
                            document: document) != nil else { continue }
            surfaces.append(surface)
        }
        return surfaces
    }

    static func preferredSurface(
        original: String, proposed: String, document: DocumentParseResult
    ) -> String {
        guard Data(original.utf8) == Data(proposed.utf8) else { return proposed }
        let surfaces = supportedReviewSurfaces(original: original, document: document)
        return surfaces.count == 2 ? surfaces[1] : proposed
    }

    static func reviewContext(
        terms: [String], document: DocumentParseResult, limit: Int = 4000
    ) -> String {
        guard limit > 0, let spans = ProtocolDocumentTermCleaner.sourceSpans(document)
        else { return "" }
        var result = ""
        var count = 0
        for span in spans {
            let text = document.blocks[span.blockIndex].text
            guard terms.contains(where: {
                !$0.isEmpty && text.range(of: $0, options: .literal) != nil
            })
            else { continue }
            let length = text.unicodeScalars.count + (result.isEmpty ? 0 : 1)
            guard length <= limit - count else { continue }
            if !result.isEmpty { result.append("\n") }
            result.append(text)
            count += length
        }
        return result
    }
}

nonisolated private struct TermCompletionSourceContext {
    private static let word = #"[\p{L}\p{M}\p{N}_]"#
    static let concentrationUnitPattern = #"(?:%|mM|µM|μM|uM|M|mg/mL|mg/L|g/L|g/mL|mol/L|mmol/L)"#
    let source: String
    let blocks: [Range<Int>]

    init(source: String, blocks: [Range<Int>]) {
        self.source = source
        let count = source.unicodeScalars.count
        self.blocks = blocks.filter { $0.lowerBound >= 0 && $0.upperBound <= count }
    }

    func exactMentionRanges(_ term: String) -> [Range<Int>] {
        guard !term.isEmpty else { return [] }
        let pattern = NSRegularExpression.escapedPattern(for: term)
        return matches(pattern).compactMap { match in
            guard let range = Range(match.range, in: source),
                  Array(source[range].unicodeScalars) == Array(term.unicodeScalars)
            else { return nil }
            return unicodeScalarRange(range)
        }
    }

    func completionEvidenceRange(original: String, proposed: String) -> Range<Int>? {
        guard !original.isEmpty, !proposed.isEmpty else { return nil }
        let candidates = supportedCompletionCandidates(original: original)
        let mentions = exactMentionRanges(original)
        guard !mentions.isEmpty else { return nil }
        var evidence: Range<Int>?
        for mention in mentions {
            let containingCompletions = candidates.filter {
                $0.1.lowerBound <= mention.lowerBound && mention.upperBound <= $0.1.upperBound
            }
            guard !containingCompletions.isEmpty, containingCompletions.allSatisfy({
                Array($0.0.unicodeScalars) == Array(proposed.unicodeScalars)
            }) else { return nil }
            if let first = containingCompletions.min(by: { $0.1.lowerBound < $1.1.lowerBound }),
               first.1.lowerBound < (evidence?.lowerBound ?? Int.max) {
                evidence = first.1
            }
        }
        return evidence
    }

    func supportedCompletionCandidates(original: String) -> [(String, Range<Int>)] {
        let escaped = NSRegularExpression.escapedPattern(for: original)
        let concentrationPattern = #"[0-9]+(?:\.[0-9]+)?[ ]*"# + Self.concentrationUnitPattern
        let hasParenthesis = original.contains { "(（".contains($0) }
        if !hasParenthesis,
           original.range(of: concentrationPattern, options: .regularExpression) != nil {
            return []
        }
        var patterns = [
            escaped + #"[ ]*[（(][^()（）\n\t]{1,80}[)）]"#,
            concentrationPattern + "[ ]+" + escaped,
            escaped + "[ ]+" + concentrationPattern
        ]
        if hasParenthesis {
            patterns.append(escaped + #"[^()（）\n\t]{0,80}[)）]"#)
        }
        return patterns.flatMap { pattern in
            matches("(?<!\(Self.word))(?:" + pattern + ")(?!\(Self.word))")
        }.filter { match in
            guard isContainedCompletion(match.range), let range = Range(match.range, in: source)
            else { return false }
            let text = String(source[range])
            guard isSupportedSurface(text, concentrationPattern: concentrationPattern)
            else { return false }
            return text.range(of: concentrationPattern, options: .regularExpression) == nil
                ? !hasAmbiguousSuffix(after: range, concentrationPattern: concentrationPattern)
                : hasUnambiguousQuantityContext(range, concentrationPattern: concentrationPattern)
        }.compactMap { match -> (String, Range<Int>)? in
            guard let range = Range(match.range, in: source), let span = unicodeScalarRange(range)
            else { return nil }
            return (String(source[range]), span)
        }
    }

    func hasUnambiguousQuantityContext(
        _ range: Range<String.Index>, concentrationPattern: String, quantityHead: String? = nil
    ) -> Bool {
        let precedingText = String(source[..<range.lowerBound].reversed()
            .drop(while: \.isWhitespace).prefix(80).reversed())
        let incompleteQuantitySuffixPattern =
            #"(?:[-+±~≈<>=≤≥–—−/^.,×·]|\b(?:or|and|equivalent)|또는|혹은)\s*$"#
        guard precedingText.range(of: incompleteQuantitySuffixPattern,
                         options: [.regularExpression, .caseInsensitive]) == nil,
              (quantityHead ?? precedingText).range(
                of: concentrationPattern + "[ ]*$", options: .regularExpression) == nil
        else { return false }
        return !hasAmbiguousSuffix(after: range, concentrationPattern: concentrationPattern)
    }

    private func hasAmbiguousSuffix(
        after range: Range<String.Index>, concentrationPattern: String
    ) -> Bool {
        let followingText = String(source[range.upperBound...]
            .drop(while: \.isWhitespace).prefix(80))
        if followingText.range(of: #"^(?:/|or\b|and\b|equivalent\b|또는|혹은)"#,
                      options: [.regularExpression, .caseInsensitive]) != nil { return true }
        guard let span = unicodeScalarRange(range), let block = blocks.first(where: {
            $0.lowerBound <= span.lowerBound && span.upperBound <= $0.upperBound
        }) else { return true }
        let followingBlockScalars = source.unicodeScalars.dropFirst(span.upperBound)
            .prefix(block.upperBound - span.upperBound)
            .drop(while: \.properties.isWhitespace).prefix(80)
        return String(String.UnicodeScalarView(followingBlockScalars)).range(
            of: #"^(?:[（(]|[→⇌]|->|"# + concentrationPattern + ")",
            options: .regularExpression
        ) != nil
    }

    func isSupportedSurface(
        _ text: String, concentrationPattern: String, concentrationOnly: Bool = false
    ) -> Bool {
        let termNamePattern = #"[\p{L}\p{M}\p{N}_µμ%/.-]+(?:[ ][\p{L}\p{M}\p{N}_µμ%/.-]+)*"#
        let instrumentMethodPattern = #"(?:[\p{L}\p{M}]+(?:식|형|법)|"#
            + #"[A-Za-z]+(?:[ -][A-Za-z]+)?[ -](?:type|method|mode))"#
        let allowedQualifierPattern = concentrationOnly ? concentrationPattern
            : concentrationPattern + "|" + instrumentMethodPattern
        let parenthesizedTermPattern = termNamePattern + #"[ ]*(?:\((?:"# + allowedQualifierPattern
            + #")\)|（(?:"# + allowedQualifierPattern + ")）)"
        let pattern = "^(?:" + parenthesizedTermPattern + "|"
            + concentrationPattern + "[ ]+" + termNamePattern
            + "|" + termNamePattern + "[ ]+" + concentrationPattern
            + (concentrationOnly ? #")\z"# : ")$")
        return text.range(of: pattern, options: .regularExpression) != nil
            && text.range(
                of: #"\b(?:or|and|equivalent)\b|또는|혹은"#,
                options: [.regularExpression, .caseInsensitive]
            ) == nil
    }

    private func unicodeScalarRange(_ range: Range<String.Index>) -> Range<Int>? {
        let sourceScalars = source.unicodeScalars
        guard let start = range.lowerBound.samePosition(in: sourceScalars),
              let end = range.upperBound.samePosition(in: sourceScalars) else { return nil }
        let scalarStartIndex = sourceScalars.distance(from: sourceScalars.startIndex, to: start)
        let scalarEndIndex = sourceScalars.distance(from: sourceScalars.startIndex, to: end)
        return scalarStartIndex..<scalarEndIndex
    }

    private func matches(_ pattern: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
    }

    func isContainedCompletion(_ match: NSRange) -> Bool {
        guard let range = Range(match, in: source),
              let scalarStartIndex = range.lowerBound.samePosition(in: source.unicodeScalars),
              let scalarEndIndex = range.upperBound.samePosition(in: source.unicodeScalars) else {
            return false
        }
        if range.upperBound < source.endIndex,
           ")]）}".contains(source[range.upperBound]) { return false }
        let sourceScalars = source.unicodeScalars
        let start = sourceScalars.distance(from: sourceScalars.startIndex, to: scalarStartIndex)
        let end = sourceScalars.distance(from: sourceScalars.startIndex, to: scalarEndIndex)
        let span = start..<end
        return blocks.contains { $0.lowerBound <= span.lowerBound
            && span.upperBound <= $0.upperBound }
    }
}
