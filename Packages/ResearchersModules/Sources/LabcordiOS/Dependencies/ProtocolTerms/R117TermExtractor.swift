import Foundation
import NaturalLanguage
import OSLog

/// 파싱된 원문에서 전체 후보를 생성하고 seed42 점수와 최종 선택 규칙을 적용합니다.
nonisolated public final class R117TermExtractor: Sendable {
    public static let shared = R117TermExtractor()
    /// 압축본 same87 한영 동일 가중 Recall@50 기준으로 선택한 배포 head입니다.
    public static let deploymentHeadFunction = "r117_seed42"
    static var resourceDirectory: URL? {
        Bundle.module.url(forResource: "R117", withExtension: nil)
    }
    private let runtime = R117ExtractionRuntime()

    public func extract(
        from text: String, progress: ProtocolTermClient.Progress? = nil
    ) async throws -> [String] {
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return try await runtime.extract(text, progress: progress)
    }
}

nonisolated public enum R117ExtractionError: LocalizedError, Sendable {
    case resourcesUnavailable

    public var errorDescription: String? {
        "용어 추출 기능을 사용할 수 없어요. 용어를 직접 입력해 주세요."
    }
}

private actor R117ExtractionRuntime {
    private var generator: R117NativeCandidateGenerator?
    private var ranker: R117Ranker?
    private let logger = Logger(subsystem: "com.labcord", category: "R117")

    func extract(
        _ text: String, progress: ProtocolTermClient.Progress?
    ) async throws -> [String] {
        let clock = ContinuousClock()
        let started = clock.now
        defer {
            let elapsed = String(describing: started.duration(to: clock.now))
            logger.info("R117 extraction finished after \(elapsed, privacy: .public)")
        }
        try Task.checkCancellation()
        guard let resources = R117TermExtractor.resourceDirectory else {
            throw R117ExtractionError.resourcesUnavailable
        }
        let generator: R117NativeCandidateGenerator
        if let cached = self.generator {
            generator = cached
        } else {
            generator = R117NativeCandidateGenerator(resourceDirectory: resources)
            self.generator = generator
        }
        let language = NLLanguageRecognizer.dominantLanguage(for: text) == .korean ? "ko" : "en"
        let pool = try await generator.generate(text: text, language: language, progress: progress)
        try Task.checkCancellation()
        let groups = try R117ShortlistBuilder.build(source: text, pool: pool)
        guard !groups.isEmpty else { return [] }
        let spans = try groups.map { group -> R117CandidateSpan in
            guard let mention = group.featureMention else {
                throw R117RuntimeError.invalidCandidate
            }
            return R117CandidateSpan(
                surface: mention.surface, start: mention.start, end: mention.end
            )
        }
        let ranker = try await preparedRanker(resources: resources, progress: progress)
        await progress?(.rankingCandidates(groups.count))
        try Task.checkCancellation()
        let result = try await score(ranker, text: text, spans: spans, progress: progress)
        let sourceScalars = Array(text.unicodeScalars)
        let candidates = try groups.enumerated().map { index, group in
            try group.selectionCandidate(index: index, sourceScalars: sourceScalars,
                                         frozenScore: result.frozenScores[index])
        }
        let selected = try R117Selector.select(
            from: candidates, source: text, scores: result.scores
        )
        try Task.checkCancellation()
        return selected.map { candidates[$0].text }
    }

    private func score(
        _ ranker: R117Ranker, text: String, spans: [R117CandidateSpan],
        progress: ProtocolTermClient.Progress?
    ) async throws -> R117Ranker.Result {
        guard let progress else {
            return try await ranker.scoresConcurrently(
                text: text, spans: spans, contextMode: .documentSharedRefined(limit: 100)
            )
        }
        let (events, continuation) = AsyncStream<(Int, Int)>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let forwarder = Task.detached {
            for await (completed, total) in events {
                await progress(.rankingProgress(completed: completed, total: total))
            }
        }
        let onCandidateProgress: @Sendable (Int, Int) -> Void = { completed, total in
            continuation.yield((completed, total))
        }
        do {
            let result = try await ranker.scoresConcurrently(
                text: text, spans: spans, contextMode: .documentSharedRefined(limit: 100),
                candidateProgress: onCandidateProgress
            )
            continuation.finish()
            await forwarder.value
            return result
        } catch {
            continuation.finish()
            forwarder.cancel()
            await forwarder.value
            throw error
        }
    }

    private func preparedRanker(
        resources: URL, progress: ProtocolTermClient.Progress?
    ) async throws -> R117Ranker {
        if let cached = ranker { return cached }
        await progress?(.preparingRanking)
        try Task.checkCancellation()
        if let cached = ranker { return cached }
        let loaded = try R117Ranker(resourceDirectory: resources)
        ranker = loaded
        return loaded
    }
}
