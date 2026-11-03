import Dispatch
import Foundation

/// 모든 후보의 특징·점수 배열은 같은 순서를 유지합니다.
nonisolated final class R117Ranker {
    enum ContextMode: Equatable, Sendable {
        case candidate
        case documentShared
        case documentSharedRefined(limit: Int)

        func forCandidateCount(_ count: Int) throws -> Self {
            guard count > 0 else { throw R117RuntimeError.invalidCandidate }
            guard case let .documentSharedRefined(limit) = self else { return self }
            guard limit > 0 else { throw R117ScoringError.invalidFeatures }
            return count <= limit ? .candidate : self
        }
    }

    private let runner: R117HeadRunner
    private let encoder: R117Encoder
    private let frozenModel: Data

    init(resourceDirectory: URL) throws {
        runner = try R117HeadRunner(resourceDirectory: resourceDirectory)
        let tokenizer = try R117Tokenizer(
            url: resourceDirectory.appendingPathComponent("tokenizer/tokenizer.json")
        )
        encoder = R117Encoder(tokenizer: tokenizer, runner: runner)
        frozenModel = try Data(
            contentsOf: resourceDirectory.appendingPathComponent("frozen9.model.json")
        )
    }

    func scores(
        text: String,
        spans: [R117CandidateSpan],
        observation: ((String, Double) -> Void)? = nil,
        includeTrace: Bool = false,
        precomputedLast2: [[Float]]? = nil,
        precomputedDocuments: Documents? = nil,
        candidateProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> Result {
        try Task.checkCancellation()
        guard !spans.isEmpty else { throw R117RuntimeError.invalidCandidate }
        let ranges = spans.map { $0.start..<$0.end }
        let original = try document(
            text: text, function: "r117_original", precomputed: precomputedDocuments?.original,
            observation: observation
        )
        let originalFeatures = try measure("original_relative_features", observation) {
            try original.relativeFeatures(text: text, spans: ranges)
        }
        let head = try measure("deployment_head", observation) {
            try runner.predictHead(
                function: R117TermExtractor.deploymentHeadFunction, features: originalFeatures
            )
        }
        let components = try teacherComponents(
            text: text, spans: spans, ranges: ranges, observation: observation,
            input: TeacherInput(
                document: precomputedDocuments?.teacher, last2Features: precomputedLast2,
                progress: candidateProgress
            )
        )
        let combined = try measure("score_combination", observation) {
            try R117ScoringMath.combine(components, headLogits: head)
        }
        return Result(
            scores: combined,
            frozenScores: components.frozen9,
            trace: includeTrace ? Trace(components: components, headLogits: head) : nil
        )
    }

    /// 공유 문맥은 문서 모델과 함께 실행하고 가변 모델 캐시 접근은 호출 actor에 남깁니다.
    func scoresConcurrently(
        text: String,
        spans: [R117CandidateSpan],
        contextMode: ContextMode = .candidate,
        isolation: isolated (any Actor)? = #isolation,
        observation: ((String, Double) -> Void)? = nil,
        includeTrace: Bool = false,
        candidateProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> Result {
        try Task.checkCancellation()
        guard !spans.isEmpty else { throw R117RuntimeError.invalidCandidate }
        let contextMode = try contextMode.forCandidateCount(spans.count)
        let ranges = spans.map { $0.start..<$0.end }
        let (documents, features) = try await encodingsConcurrently(
            text: text, ranges: ranges, mode: contextMode,
            observation: observation, progress: candidateProgress
        )
        try Task.checkCancellation()
        let refinementLimit: Int?
        if case let .documentSharedRefined(limit) = contextMode {
            refinementLimit = limit
        } else {
            refinementLimit = nil
        }
        let result = try scores(
            text: text, spans: spans, observation: observation,
            includeTrace: includeTrace || refinementLimit != nil, precomputedLast2: features,
            precomputedDocuments: documents
        )
        guard let refinementLimit else { return result }
        return try await refine(
            text: text, observation: observation,
            input: RefinementInput(
                ranges: ranges, coarse: result, limit: refinementLimit,
                includeTrace: includeTrace, progress: candidateProgress
            )
        )
    }

    struct Documents: Sendable {
        let original: R117Encoder.Document
        let teacher: R117Encoder.Document
    }

    struct Result {
        let scores: [Double]
        let frozenScores: [Double]
        let trace: Trace?
    }

    struct Trace {
        let components: R117ScoringMath.Components
        let headLogits: [Double]
    }

    struct RefinementPlan: Sendable {
        let indices: [Int]
        let total: Int

        var completedBeforeRefinement: Int { total - indices.count }

        init(scores: [Double], limit: Int) throws {
            guard limit > 0, !scores.isEmpty, scores.allSatisfy(\.isFinite) else {
                throw R117ScoringError.invalidFeatures
            }
            total = scores.count
            indices = Array(scores.indices.sorted {
                scores[$0] == scores[$1] ? $0 < $1 : scores[$0] > scores[$1]
            }.prefix(limit))
        }

        func replacingLast2(in trace: Trace, with logits: [Double]) throws -> Trace {
            let values = trace.components
            let arrays = [
                values.native, values.frozen9, values.hgb, values.window,
                values.scope, values.purpose, values.last2, trace.headLogits
            ]
            guard arrays.allSatisfy({
                $0.count == total && $0.allSatisfy(\.isFinite)
            }), logits.count == indices.count, logits.allSatisfy(\.isFinite) else {
                throw R117ScoringError.invalidModelOutput
            }
            var last2 = values.last2
            for (index, logit) in zip(indices, logits) { last2[index] = logit }
            return Trace(
                components: R117ScoringMath.Components(
                    native: values.native, frozen9: values.frozen9, hgb: values.hgb,
                    window: values.window, scope: values.scope, purpose: values.purpose,
                    last2: last2
                ), headLogits: trace.headLogits
            )
        }
    }
}

nonisolated private extension R117Ranker {
    func encodingsConcurrently(
        text: String, ranges: [Range<Int>], mode: ContextMode,
        isolation: isolated (any Actor)? = #isolation,
        observation: ((String, Double) -> Void)?, progress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> (Documents, [[Float]]) {
        let documents: Documents
        let features: [[Float]]
        if mode == .candidate {
            documents = try await documentsConcurrently(text: text, observation: observation)
            features = try await last2Concurrently(
                text: text, ranges: ranges,
                observation: observation, progress: progress
            )
        } else {
            let documentStart = DispatchTime.now().uptimeNanoseconds
            let prepared = try encoder.prepareDocuments(text: text)
            let documentPreparation = Double(DispatchTime.now().uptimeNanoseconds
                - documentStart) / 1_000_000_000
            let sharedStart = DispatchTime.now().uptimeNanoseconds
            let shared = try encoder.prepareShared(text: text)
            let sharedPreparation = Double(DispatchTime.now().uptimeNanoseconds
                - sharedStart) / 1_000_000_000
            let sharedProgress = mode == .documentShared ? progress : nil
            async let documentResult = R117Encoder.runDocuments(
                original: prepared.original, teacher: prepared.teacher
            )
            async let sharedResult = R117Encoder.runShared(
                prepared: shared, ranges: ranges, progress: sharedProgress
            )
            let (documentOutput, sharedOutput) = try await (documentResult, sharedResult)
            try Task.checkCancellation()
            documents = Documents(original: documentOutput.value.original,
                                  teacher: documentOutput.value.teacher)
            features = sharedOutput.value
            observation?("document_encoder_preparation", documentPreparation)
            observation?("shared_encoder_preparation", sharedPreparation)
            observation?("document_encoders_concurrent",
                         documentPreparation + documentOutput.duration)
            observation?("teacher_last2_features", sharedPreparation + sharedOutput.duration)
        }
        return (documents, features)
    }

    func documentsConcurrently(
        text: String, isolation: isolated (any Actor)? = #isolation,
        observation: ((String, Double) -> Void)?
    ) async throws -> Documents {
        let started = observation == nil ? nil : DispatchTime.now().uptimeNanoseconds
        let prepared = try encoder.prepareDocuments(text: text)
        async let original = prepared.original.document()
        async let teacher = prepared.teacher.document()
        let (originalDocument, teacherDocument) = try await (original, teacher)
        try Task.checkCancellation()
        if let started {
            observation?("document_encoders_concurrent",
                         Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000)
        }
        return Documents(original: originalDocument, teacher: teacherDocument)
    }

    func last2Concurrently(
        text: String, ranges: [Range<Int>],
        isolation: isolated (any Actor)? = #isolation,
        observation: ((String, Double) -> Void)?, progress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> [[Float]] {
        let started = observation == nil ? nil : DispatchTime.now().uptimeNanoseconds
        let features = try await encoder.last2Concurrently(
            text: text, spans: ranges, progress: progress
        )
        if let started {
            observation?("teacher_last2_features",
                         Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000)
        }
        return features
    }

    func refine(
        text: String, isolation: isolated (any Actor)? = #isolation,
        observation: ((String, Double) -> Void)?, input: RefinementInput
    ) async throws -> Result {
        try Task.checkCancellation()
        let coarse = input.coarse
        let plan = try RefinementPlan(scores: coarse.scores, limit: input.limit)
        guard let trace = coarse.trace, input.ranges.count == plan.total,
              coarse.frozenScores.count == plan.total,
              coarse.frozenScores.allSatisfy(\.isFinite) else {
            throw R117ScoringError.invalidModelOutput
        }
        let offset = plan.completedBeforeRefinement
        let progress = input.progress
        try Task.checkCancellation()
        progress?(offset, plan.total)
        let started = observation == nil ? nil : DispatchTime.now().uptimeNanoseconds
        let features = try await encoder.last2Concurrently(
            text: text, spans: plan.indices.map { input.ranges[$0] }
        ) { completed, _ in progress?(offset + completed, plan.total) }
        try Task.checkCancellation()
        if let started {
            observation?("teacher_last2_refinement_features",
                         Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000)
        }
        let logits = try measure("teacher_last2_refinement_head", observation) {
            try runner.predictHead(
                function: "teacher_last2_head", features: features, inputName: "pooled_features"
            )
        }
        try Task.checkCancellation()
        let refined = try plan.replacingLast2(in: trace, with: logits)
        let combined = try measure("score_refinement_combination", observation) {
            try R117ScoringMath.combine(refined.components, headLogits: refined.headLogits)
        }
        try Task.checkCancellation()
        return Result(
            scores: combined, frozenScores: coarse.frozenScores,
            trace: input.includeTrace ? refined : nil
        )
    }

    struct RefinementInput {
        let ranges: [Range<Int>]
        let coarse: Result
        let limit: Int
        let includeTrace: Bool
        let progress: (@Sendable (Int, Int) -> Void)?
    }

    func teacherComponents(
        text: String,
        spans: [R117CandidateSpan],
        ranges: [Range<Int>],
        observation: ((String, Double) -> Void)?,
        input: TeacherInput
    ) throws -> R117ScoringMath.Components {
        let teacher = try document(
            text: text, function: "teacher_taskfit", precomputed: input.document,
            observation: observation
        )
        let relative = try measure("teacher_relative_features", observation) {
            try teacher.relativeFeatures(text: text, spans: ranges)
        }
        let purposeRelative = try measure("teacher_purpose_features", observation) {
            try teacher.relativeFeatures(text: text, spans: ranges, contextTokenLimit: 512)
        }
        let native = try measure("native_features", observation) {
            try R117ScoringMath.native(count: spans.count)
        }
        let featureDocument = R117HandcraftedFeatures.Document(text: text)
        let nine = try measure("handcrafted_nine", observation) {
            try spans.map { try featureDocument.nine(span: $0) }
        }
        let frozen = try measure("frozen9", observation) {
            try R117ScoringMath.frozen9(features: nine, modelData: frozenModel)
        }
        let features = try measure("handcrafted_32", observation) {
            try spans.map { try featureDocument.combined32(span: $0) }
        }
        let hgb = try measure("teacher_hgb", observation) {
            try runner.predictHGB(features: features)
        }
        let window = try measure("teacher_window_head", observation) {
            try runner.predictHead(function: "teacher_window", features: relative)
        }
        let scope = try measure("teacher_scope_head", observation) {
            try runner.predictHead(function: "teacher_scope", features: relative)
        }
        let purpose = try measure("teacher_purpose_head", observation) {
            try runner.predictHead(function: "teacher_purpose", features: purposeRelative)
        }
        let last2Features = try last2Features(
            text: text, ranges: ranges, observation: observation, input: input
        )
        let last2 = try measure("teacher_last2_head", observation) {
            try runner.predictHead(
                function: "teacher_last2_head", features: last2Features,
                inputName: "pooled_features"
            )
        }
        return R117ScoringMath.Components(
            native: native, frozen9: frozen, hgb: hgb, window: window,
            scope: scope, purpose: purpose, last2: last2
        )
    }

    struct TeacherInput {
        let document: R117Encoder.Document?
        let last2Features: [[Float]]?
        let progress: (@Sendable (Int, Int) -> Void)?
    }

    func last2Features(
        text: String, ranges: [Range<Int>], observation: ((String, Double) -> Void)?,
        input: TeacherInput
    ) throws -> [[Float]] {
        if let features = input.last2Features { return features }
        return try measure("teacher_last2_features", observation) {
            try encoder.last2(text: text, spans: ranges, progress: input.progress)
        }
    }

    func document(
        text: String, function: String, precomputed: R117Encoder.Document?,
        observation: ((String, Double) -> Void)?
    ) throws -> R117Encoder.Document {
        if let precomputed { return precomputed }
        let stage = function == "r117_original"
            ? "original_document_encoder" : "teacher_document_encoder"
        return try measure(stage, observation) {
            try encoder.document(text: text, function: function)
        }
    }

    func measure<T>(
        _ stage: String, _ observation: ((String, Double) -> Void)?, _ operation: () throws -> T
    ) rethrows -> T {
        guard let observation else { return try operation() }
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            observation(stage, Double(elapsed) / 1_000_000_000)
        }
        return try operation()
    }
}
