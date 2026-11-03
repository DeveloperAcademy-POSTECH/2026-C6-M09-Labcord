import CoreML
import Foundation

/// 같은 입력은 한 번만 추론하며, 최대 네 모델에 모델당 async prediction 두 개를 배정합니다.
nonisolated enum R117ConcurrentEncoder {
    struct Features: Sendable {
        let candidate: Int
        let values: [Float]
    }

    typealias Prediction = @Sendable (R117Last2Plan.Group) async throws -> [Features]
    typealias WorkerPrediction = @Sendable (R117Last2Plan.Group, Int) async throws -> [Features]

    static func last2(
        plan: R117Last2Plan, model: MLModel, candidateCount: Int,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [[Float]] {
        try await last2(plan: plan, models: [model], candidateCount: candidateCount,
                        progress: progress)
    }

    static func last2(
        plan: R117Last2Plan, models: [MLModel], candidateCount: Int,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [[Float]] {
        try Task.checkCancellation()
        guard (1...4).contains(models.count),
              Set(models.map { ObjectIdentifier($0) }).count == models.count else {
            throw R117RuntimeError.invalidCandidate
        }
        let predictors = models.map { AsyncModel(model: $0) }
        return try await last2(
            plan: plan, workerCount: predictors.count,
            candidateCount: candidateCount, progress: progress
        ) { group, worker in
            try await predictors[worker].predict(group)
        }
    }

    static func last2(
        plan: R117Last2Plan, candidateCount: Int,
        progress: (@Sendable (Int, Int) -> Void)? = nil,
        prediction: @escaping Prediction
    ) async throws -> [[Float]] {
        try await last2(plan: plan, workerCount: 1, candidateCount: candidateCount,
                        progress: progress) { group, _ in try await prediction(group) }
    }

    static func last2(
        plan: R117Last2Plan, workerCount: Int, candidateCount: Int,
        progress: (@Sendable (Int, Int) -> Void)? = nil,
        prediction: @escaping WorkerPrediction
    ) async throws -> [[Float]] {
        try Task.checkCancellation()
        guard (1...4).contains(workerCount) else { throw R117RuntimeError.invalidCandidate }
        try validate(plan, candidateCount: candidateCount)
        return try await run(plan: plan, workerCount: workerCount, candidateCount: candidateCount,
                             progress: progress, prediction: prediction)
    }
}

private extension R117ConcurrentEncoder {
    private struct CompletedGroup: Sendable {
        let group: R117Last2Plan.Group
        let worker: Int
        let features: [Features]
    }

    private static func run(
        plan: R117Last2Plan, workerCount: Int, candidateCount: Int,
        progress: (@Sendable (Int, Int) -> Void)?, prediction: @escaping WorkerPrediction
    ) async throws -> [[Float]] {
        return try await withThrowingTaskGroup(of: CompletedGroup.self) { tasks in
            var rows: [[Float]?] = Array(repeating: nil, count: candidateCount)
            var next = min(2 * workerCount, plan.groups.count)
            var completed = 0
            var nextProgress = 20
            for index in 0..<next {
                submit(plan.groups[index], worker: index % workerCount,
                       to: &tasks, prediction: prediction)
            }
            while let result = try await tasks.next() {
                try Task.checkCancellation()
                try store(result, in: &rows)
                completed += result.features.count
                if completed >= nextProgress || completed == candidateCount {
                    try Task.checkCancellation()
                    progress?(completed, candidateCount)
                    try Task.checkCancellation()
                    nextProgress = completed + 20
                }
                if next < plan.groups.count {
                    try Task.checkCancellation()
                    submit(plan.groups[next], worker: result.worker,
                           to: &tasks, prediction: prediction)
                    next += 1
                }
            }
            try Task.checkCancellation()
            return try rows.map { row in
                guard let row else { throw R117RuntimeError.invalidModelOutput }
                return row
            }
        }
    }

    private static func validate(_ plan: R117Last2Plan, candidateCount: Int) throws {
        guard candidateCount >= 0 else { throw R117RuntimeError.invalidCandidate }
        let candidates = plan.groups.flatMap { $0.selections.map(\.candidate) }
        guard candidates.count == candidateCount, Set(candidates).count == candidateCount,
              candidates.allSatisfy({ (0..<candidateCount).contains($0) }) else {
            throw R117RuntimeError.invalidCandidate
        }
    }

    private static func submit(
        _ group: R117Last2Plan.Group, worker: Int,
        to tasks: inout ThrowingTaskGroup<CompletedGroup, Error>,
        prediction: @escaping WorkerPrediction
    ) {
        tasks.addTask {
            try Task.checkCancellation()
            let features = try await prediction(group, worker)
            try Task.checkCancellation()
            return CompletedGroup(group: group, worker: worker, features: features)
        }
    }

    private static func store(_ result: CompletedGroup, in rows: inout [[Float]?]) throws {
        let expected = Set(result.group.selections.map(\.candidate))
        guard result.features.count == expected.count else {
            throw R117RuntimeError.invalidModelOutput
        }
        for features in result.features {
            guard expected.contains(features.candidate), rows.indices.contains(features.candidate),
                  rows[features.candidate] == nil, features.values.count == 384,
                  features.values.allSatisfy(\.isFinite) else {
                throw R117RuntimeError.invalidModelOutput
            }
            rows[features.candidate] = features.values
        }
    }

    // 공유 모델은 Apple이 동시 호출을 지원하는 async API로만 사용합니다.
    // https://developer.apple.com/videos/play/wwdc2023/10049/
    // SDK가 모델의 Sendable 적합성을 제공하면 이 한정 wrapper를 제거합니다.
    private final class AsyncModel: @unchecked Sendable {
        private let model: MLModel

        init(model: MLModel) {
            self.model = model
        }

        func predict(_ group: R117Last2Plan.Group) async throws -> [Features] {
            try Task.checkCancellation()
            let input = try R117Tensor.input(ids: group.ids)
            let prediction = try await model.prediction(
                from: input, options: MLPredictionOptions()
            )
            try Task.checkCancellation()
            let output = try R117Tensor.embeddings(from: prediction, length: group.ids.count)
            return try group.selections.map { selection in
                try Task.checkCancellation()
                return Features(
                    candidate: selection.candidate,
                    values: R117Tensor.pooled(output, selected: selection.tokens)
                )
            }
        }
    }
}
