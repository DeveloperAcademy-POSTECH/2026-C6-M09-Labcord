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
