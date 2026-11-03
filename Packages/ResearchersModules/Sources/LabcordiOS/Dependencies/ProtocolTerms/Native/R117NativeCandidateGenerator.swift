import CoreML
import Foundation

/// 후보 위치는 원문 Unicode scalar offset입니다.
nonisolated struct R117NativeRawCandidate: Sendable {
    let start: Int
    let end: Int
    let score: Double
    let kind: String
    let tier: Int
    let retained: Bool
}

nonisolated struct R117NativeCandidatePool: Sendable {
    let rawCandidates: [R117NativeRawCandidate]
    let nativeOrder: [String]
    let guardedOrder: [String]

    static func records(
        merged: [MergedCandidate], scalars: [Unicode.Scalar], language: String
    ) throws -> (raw: [R117NativeRawCandidate], cached: [CachedCandidate]) {
        var raw: [R117NativeRawCandidate] = []
        var cached: [CachedCandidate] = []
        raw.reserveCapacity(merged.count)
        cached.reserveCapacity(merged.count)
        for candidate in merged {
            guard candidate.start >= 0, candidate.end > candidate.start,
                  candidate.end <= scalars.count, candidate.score.isFinite else {
                throw R117NativeError.invalidPrediction
            }
            let norm = HintNorm.norm(TermHintDecoder.sliceStr(
                scalars, candidate.start, candidate.end
            ))
            let decision = AdmissionDecision.decide(AdmissionInput(
                chars: scalars, language: language, start: candidate.start, end: candidate.end,
                score: candidate.score, noFilter: candidate.noFilter, norm: norm
            ))
            let score = Double(candidate.score)
            raw.append(R117NativeRawCandidate(
                start: candidate.start, end: candidate.end, score: score,
                kind: candidate.kind, tier: candidate.tier, retained: decision.retained
            ))
            cached.append(CachedCandidate(
                start: candidate.start, end: candidate.end, score: score,
                admitted: decision.admitted, norm: norm
            ))
        }
        return (raw, cached)
    }
}

/// Legacy decoder의 가변 설정은 모든 인스턴스가 같은 worker에서 직렬 실행합니다.
actor R117NativeCandidateGenerator {
    private let resourceDirectory: URL

    init(resourceDirectory: URL) {
        self.resourceDirectory = resourceDirectory
    }

    func generate(
        text: String, language: String, progress: ProtocolTermClient.Progress? = nil
    ) async throws -> R117NativeCandidatePool {
        try await R117NativeWorker.shared.generate(
            text: text, language: language,
            resourceDirectory: resourceDirectory, progress: progress
        )
    }
}

private actor R117NativeWorker {
    static let shared = R117NativeWorker()
    private var pipelines: [URL: R117NativePipeline] = [:]

    func generate(
        text: String, language: String, resourceDirectory: URL,
        progress: ProtocolTermClient.Progress?
    ) async throws -> R117NativeCandidatePool {
        try Task.checkCancellation()
        if pipelines[resourceDirectory] == nil {
            await progress?(.preparingExtraction)
            try Task.checkCancellation()
        }
        let pipeline: R117NativePipeline
        if let cached = pipelines[resourceDirectory] {
            pipeline = cached
        } else {
            pipeline = try R117NativePipeline(resourceDirectory: resourceDirectory)
            pipelines[resourceDirectory] = pipeline
        }
        await progress?(.extractingCandidates)
        try Task.checkCancellation()
        // Decoder 전역 설정부터 후보 생성·정리까지는 suspension 없이 같은 worker에서 실행합니다.
        return try pipeline.generate(text: text, language: language)
    }
}

nonisolated enum R117NativeError: Error {
    case invalidResource
    case invalidPrediction
    case unsupportedLanguage
}

nonisolated private final class R117NativePipeline {
    private let pipeline: TermHintPipeline
    private let priority: SectionPriority
    private let knownTerms: Set<String>
    private let knownBonus: Float

    init(resourceDirectory: URL) throws {
        let assets = resourceDirectory.appendingPathComponent("native-assets")
        let decoder = JSONDecoder()
        let sectionURL = assets.appendingPathComponent("section_priority_rules.json")
        let koreanURL = assets.appendingPathComponent("korean_rules.json")
        priority = try SectionPriority(
            rules: decoder.decode(PriorityRules.self, from: Data(contentsOf: sectionURL)),
            koreanRules: decoder.decode(KoreanHeadingRules.self, from: Data(contentsOf: koreanURL))
        )
        let knownURL = assets.appendingPathComponent("known_terms.json")
        let dictionary = try JSONSerialization.jsonObject(with: Data(contentsOf: knownURL))
            as? [String: Any]
        guard let terms = dictionary?["terms"] as? [String] else {
            throw R117NativeError.invalidResource
        }
        knownTerms = Set(terms)
        knownBonus = (dictionary?["bonus"] as? NSNumber)?.floatValue ?? 1.5
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        pipeline = try TermHintPipeline(
            modelURL: assets.appendingPathComponent("sentencepiece.bpe.model"),
            modelPackageURL: resourceDirectory
                .appendingPathComponent("Unicode4.mlpackage"),
            charVocabURL: assets.appendingPathComponent("char_vocab.json"),
            knownTermsURL: knownURL,
            sectionPriorityRulesURL: sectionURL,
            koreanRulesURL: koreanURL,
            configuration: config
        )
    }

    func generate(text: String, language: String) throws -> R117NativeCandidatePool {
        try Task.checkCancellation()
        guard language == "ko" || language == "en" else {
            throw R117NativeError.unsupportedLanguage
        }
        TermHintDecoder.scoreMode = "mean"
        TermHintDecoder.maxWords = 0
        TermHintDecoder.knownTerms = knownTerms
        TermHintDecoder.knownBonus = knownBonus
        TermHintDecoder.debugMerged = true
        defer { TermHintDecoder.lastMerged = [] }
        let actual = pipeline.hints(for: text, language: language, K: 100)
        try Task.checkCancellation()
        guard !actual.isEmpty || text.isEmpty else { throw R117NativeError.invalidPrediction }
        let scalars = Array(text.unicodeScalars)
        let records = try R117NativeCandidatePool.records(
            merged: TermHintDecoder.lastMerged, scalars: scalars, language: language
        )
        let (ranges, _) = priority.ranges(in: text)
        let native = try priority.emitFusion(
            records.cached, text: text, localLimit: 100, ranges: ranges
        )
        guard native.map(\.text) == actual.map(\.text) else {
            throw R117NativeError.invalidPrediction
        }
        let guarded = try DocumentFrequencyRanking.hints(
            candidates: records.cached, fusion: native, text: text, limit: 100
        )
        try Task.checkCancellation()
        return R117NativeCandidatePool(
            rawCandidates: records.raw, nativeOrder: native.map(\.text),
            guardedOrder: guarded.map(\.text)
        )
    }
}
