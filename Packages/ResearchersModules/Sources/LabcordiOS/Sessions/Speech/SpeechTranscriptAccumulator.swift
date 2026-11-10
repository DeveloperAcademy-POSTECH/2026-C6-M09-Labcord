import Speech

struct SpeechTranscriptAccumulator {
    private var finalizedSegments: [String] = []
    private var volatileSegment: String?

    mutating func accept(
        _ result: DictationTranscriber.Result,
        termMatcher: inout SpeechTermMatcher,
        unitNormalizer: SpeechUnitNormalizer
    ) -> String? {
        let text = termMatcher.bestCandidate(
            primary: String(result.text.characters),
            alternatives: result.alternatives.lazy.map { String($0.characters) }
        )
        guard !text.isEmpty || result.isFinal else { return nil }

        if result.isFinal {
            if !text.isEmpty { finalizedSegments.append(text) }
            volatileSegment = nil
        } else {
            volatileSegment = text
        }
        let raw = (finalizedSegments + [volatileSegment].compactMap { $0 })
            .joined(separator: " ")
        return unitNormalizer.normalize(termMatcher.restore(raw).text)
    }
}
