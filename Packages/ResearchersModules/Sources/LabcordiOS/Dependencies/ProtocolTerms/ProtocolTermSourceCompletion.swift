import Foundation
import OmniParser

/// 모든 원문 언급이 같은 농도 완전형에 연결될 때만 표면을 복원합니다.
nonisolated enum ProtocolTermSourceCompletion {
    /// 이미 생성된 BIO 표면이 원문에 명시된 완전한 농도형인지 확인합니다.
    static func isExplicitConcentration(
        surface: String, range: Range<Int>, source: String
    ) -> Bool {
        let concentration = #"[0-9]+(?:\.[0-9]+)?[ ]*"# + TermCompletionSource.units
        let context = TermCompletionSource(
            source: source, blocks: [0..<source.unicodeScalars.count])
        guard surface.range(of: concentration, options: .regularExpression) != nil,
              context.safeSurface(surface, concentration: concentration, concentrationOnly: true),
              range.lowerBound >= 0, range.upperBound <= source.unicodeScalars.count,
              !range.isEmpty else { return false }
        let scalars = source.unicodeScalars
        let lower = scalars.index(scalars.startIndex, offsetBy: range.lowerBound)
        let upper = scalars.index(lower, offsetBy: range.count)
        guard Array(scalars[lower..<upper]) == Array(surface.unicodeScalars) else { return false }
        guard context.validCompletion(NSRange(lower..<upper, in: source)) else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: surface)
        let pattern = "(?<![\\p{L}\\p{M}\\p{N}_])" + escaped
            + "(?![\\p{L}\\p{M}\\p{N}_])"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              regex.firstMatch(in: source, options: .withTransparentBounds,
                               range: NSRange(lower..<upper, in: source)) != nil
        else { return false }
        // 다음 행의 독립된 농도 언급은 같은 표면의 대안으로 보지 않습니다.
        let end = scalars[upper...].firstIndex(of: "\n") ?? scalars.endIndex
        let local = TermCompletionSource(source: source, blocks: [0..<scalars.distance(
            from: scalars.startIndex, to: end)])
        let lineHead = String(source[..<lower].reversed().prefix { !$0.isNewline }.reversed())
        return local.validQuantityContext(
            lower..<upper, concentration: concentration, quantityHead: lineHead)
    }

    /// 원형 행은 보존하고, 치환은 모든 literal 언급이 같은 완성형을 지지할 때만 승인합니다.
    static func reviewRow(
        original: String, proposed: String, category: ProtocolTermReviewCategory,
        document: DocumentParseResult
    ) -> ProtocolTermReviewRow? {
        let unchanged = Array(original.unicodeScalars) == Array(proposed.unicodeScalars)
        let spans = ProtocolDocumentTermCleaner.sourceSpans(document) ?? []
        let context = TermCompletionSource(
            source: document.fullText, blocks: spans.map { $0.start..<$0.end }
        )
        let range = unchanged ? context.literalRanges(original).first { range in
            spans.contains { $0.start <= range.lowerBound && range.upperBound <= $0.end }
        } : context.reviewCompletion(original: original, proposed: proposed)
        let evidence = range.flatMap { range in
            spans.first { $0.start <= range.lowerBound && range.upperBound <= $0.end }.map {
                ProtocolTermSourceSpan(
                    start: range.lowerBound, end: range.upperBound, blockIndex: $0.blockIndex
                )
            }
        }
        guard unchanged || evidence != nil else { return nil }
        return ProtocolTermReviewRow(
            original: original, surface: proposed, category: category, evidence: evidence
        )
    }

    /// 기존 검증기가 승인하는 원문 표기만 열거하며 원형을 항상 첫째로 보존합니다.
    static func supportedReviewSurfaces(
        original: String, document: DocumentParseResult
    ) -> [String] {
        guard !original.isEmpty, let spans = ProtocolDocumentTermCleaner.sourceSpans(document),
              !spans.contains(where: {
                  $0.end - $0.start > 4_000 && document.blocks[$0.blockIndex].text.range(
                      of: original, options: .literal
                  ) != nil
              }) else { return [original] }
        let context = TermCompletionSource(
            source: document.fullText, blocks: spans.map { $0.start..<$0.end }
        )
        var surfaces = [original]
        var seen = Set([Data(original.utf8)])
        for (surface, _) in context.reviewCandidates(original: original) {
            guard seen.insert(Data(surface.utf8)).inserted,
                  reviewRow(original: original, proposed: surface, category: .glossary,
                            document: document) != nil else { continue }
            surfaces.append(surface)
        }
        return surfaces
    }

    /// 모든 언급이 지지하는 완성형이 하나뿐이면 원형 대신 보존합니다.
    static func preferredSurface(
        original: String, proposed: String, document: DocumentParseResult
    ) -> String {
        guard Data(original.utf8) == Data(proposed.utf8) else { return proposed }
        let surfaces = supportedReviewSurfaces(original: original, document: document)
        return surfaces.count == 2 ? surfaces[1] : proposed
    }

    /// 관련 원문 블록을 순서대로 제공하며 한도를 넘는 블록은 통째로 생략합니다.
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

nonisolated private struct TermCompletionSource {
    private static let word = #"[\p{L}\p{M}\p{N}_]"#
    static let units = #"(?:%|mM|µM|μM|uM|M|mg/mL|mg/L|g/L|g/mL|mol/L|mmol/L)"#
    let source: String
    let blocks: [Range<Int>]

    init(source: String, blocks: [Range<Int>]) {
        self.source = source
        let count = source.unicodeScalars.count
        self.blocks = blocks.filter { $0.lowerBound >= 0 && $0.upperBound <= count }
    }

    func literalRanges(_ term: String) -> [Range<Int>] {
        guard !term.isEmpty else { return [] }
        let pattern = NSRegularExpression.escapedPattern(for: term)
        return matches(pattern).compactMap { match in
            guard let range = Range(match.range, in: source),
                  Array(source[range].unicodeScalars) == Array(term.unicodeScalars)
            else { return nil }
            return scalarRange(range)
        }
    }

    func reviewCompletion(original: String, proposed: String) -> Range<Int>? {
        guard !original.isEmpty, !proposed.isEmpty else { return nil }
        let candidates = reviewCandidates(original: original)
        let mentions = literalRanges(original)
        guard !mentions.isEmpty else { return nil }
        var evidence: Range<Int>?
        for mention in mentions {
            let enclosing = candidates.filter {
                $0.1.lowerBound <= mention.lowerBound && mention.upperBound <= $0.1.upperBound
            }
            guard !enclosing.isEmpty, enclosing.allSatisfy({
                Array($0.0.unicodeScalars) == Array(proposed.unicodeScalars)
            }) else { return nil }
            // 가장 이른 원문 위치를 결정적으로 선택합니다.
            if let first = enclosing.min(by: { $0.1.lowerBound < $1.1.lowerBound }),
               first.1.lowerBound < (evidence?.lowerBound ?? Int.max) {
                evidence = first.1
            }
        }
        return evidence
    }

    func reviewCandidates(original: String) -> [(String, Range<Int>)] {
        let escaped = NSRegularExpression.escapedPattern(for: original)
        let concentration = #"[0-9]+(?:\.[0-9]+)?[ ]*"# + Self.units
        let hasParenthesis = original.contains { "(（".contains($0) }
        if !hasParenthesis,
           original.range(of: concentration, options: .regularExpression) != nil { return [] }
        var patterns = [
            escaped + #"[ ]*[（(][^()（）\n\t]{1,80}[)）]"#,
            concentration + "[ ]+" + escaped,
            escaped + "[ ]+" + concentration
        ]
        if hasParenthesis {
            patterns.append(escaped + #"[^()（）\n\t]{0,80}[)）]"#)
        }
        return patterns.flatMap { pattern in
            matches("(?<!\(Self.word))(?:" + pattern + ")(?!\(Self.word))")
        }.filter { match in
            guard validCompletion(match.range), let range = Range(match.range, in: source)
            else { return false }
            let text = String(source[range])
            guard safeSurface(text, concentration: concentration) else { return false }
            return text.range(of: concentration, options: .regularExpression) == nil
                ? !ambiguousSuffix(after: range, concentration: concentration)
                : validQuantityContext(range, concentration: concentration)
        }.compactMap { match -> (String, Range<Int>)? in
            guard let range = Range(match.range, in: source), let span = scalarRange(range)
            else { return nil }
            return (String(source[range]), span)
        }
    }

    func validQuantityContext(
        _ range: Range<String.Index>, concentration: String, quantityHead: String? = nil
    ) -> Bool {
        let head = String(source[..<range.lowerBound].reversed()
            .drop(while: \.isWhitespace).prefix(80).reversed())
        let partialQuantity = #"(?:[-+±~≈<>=≤≥–—−/^.,×·]|\b(?:or|and|equivalent)|또는|혹은)\s*$"#
        guard head.range(of: partialQuantity,
                         options: [.regularExpression, .caseInsensitive]) == nil,
              (quantityHead ?? head).range(
                of: concentration + "[ ]*$", options: .regularExpression) == nil
        else { return false }
        return !ambiguousSuffix(after: range, concentration: concentration)
    }

    private func ambiguousSuffix(
        after range: Range<String.Index>, concentration: String
    ) -> Bool {
        let tail = String(source[range.upperBound...]
            .drop(while: \.isWhitespace).prefix(80))
        if tail.range(of: #"^(?:/|or\b|and\b|equivalent\b|또는|혹은)"#,
                      options: [.regularExpression, .caseInsensitive]) != nil { return true }
        guard let span = scalarRange(range), let block = blocks.first(where: {
            $0.lowerBound <= span.lowerBound && span.upperBound <= $0.upperBound
        }) else { return true }
        let localTail = source.unicodeScalars.dropFirst(span.upperBound)
            .prefix(block.upperBound - span.upperBound)
            .drop(while: \.properties.isWhitespace).prefix(80)
        return String(String.UnicodeScalarView(localTail)).range(
            of: #"^(?:[（(]|[→⇌]|->|"# + concentration + ")",
            options: .regularExpression
        ) != nil
    }

    func safeSurface(
        _ text: String, concentration: String, concentrationOnly: Bool = false
    ) -> Bool {
        let name = #"[\p{L}\p{M}\p{N}_µμ%/.-]+(?:[ ][\p{L}\p{M}\p{N}_µμ%/.-]+)*"#
        // 방식은 짧은 문자 표기만 허용합니다. 번호, 목록, 문장, 반응식은 범위 밖입니다.
        let method = #"(?:[\p{L}\p{M}]+(?:식|형|법)|"#
            + #"[A-Za-z]+(?:[ -][A-Za-z]+)?[ -](?:type|method|mode))"#
        let qualifier = concentrationOnly ? concentration : concentration + "|" + method
        let parenthesized = name + #"[ ]*(?:\((?:"# + qualifier
            + #")\)|（(?:"# + qualifier + ")）)"
        let pattern = "^(?:" + parenthesized + "|" + concentration + "[ ]+" + name
            + "|" + name + "[ ]+" + concentration + (concentrationOnly ? #")\z"# : ")$")
        return text.range(of: pattern, options: .regularExpression) != nil
            && text.range(
                of: #"\b(?:or|and|equivalent)\b|또는|혹은"#,
                options: [.regularExpression, .caseInsensitive]
            ) == nil
    }

    private func scalarRange(_ range: Range<String.Index>) -> Range<Int>? {
        let scalars = source.unicodeScalars
        guard let start = range.lowerBound.samePosition(in: scalars),
              let end = range.upperBound.samePosition(in: scalars) else { return nil }
        let lower = scalars.distance(from: scalars.startIndex, to: start)
        let upper = scalars.distance(from: scalars.startIndex, to: end)
        return lower..<upper
    }

    private func matches(_ pattern: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
    }

    func validCompletion(_ match: NSRange) -> Bool {
        guard let range = Range(match, in: source),
              let lower = range.lowerBound.samePosition(in: source.unicodeScalars),
              let upper = range.upperBound.samePosition(in: source.unicodeScalars) else {
            return false
        }
        if range.upperBound < source.endIndex,
           ")]）}".contains(source[range.upperBound]) { return false }
        let scalars = source.unicodeScalars
        let start = scalars.distance(from: scalars.startIndex, to: lower)
        let end = scalars.distance(from: scalars.startIndex, to: upper)
        let span = start..<end
        return blocks.contains { $0.lowerBound <= span.lowerBound
            && span.upperBound <= $0.upperBound }
    }
}
