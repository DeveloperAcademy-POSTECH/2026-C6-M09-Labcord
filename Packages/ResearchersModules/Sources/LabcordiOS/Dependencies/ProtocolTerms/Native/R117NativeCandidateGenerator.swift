import CoreML
import Foundation

/// 모든 인스턴스의 모델 로딩·추론을 공유 worker에서 직렬 실행합니다.
actor R117NativeCandidateGenerator {
    private let resourceDirectory: URL

    init(resourceDirectory: URL) {
        self.resourceDirectory = resourceDirectory
    }

    func hints(
        text: String, progress: ProtocolTermClient.Progress?
    ) async throws -> [TermHint] {
        try await R117NativeWorker.shared.hints(
            text: text, resourceDirectory: resourceDirectory, progress: progress)
    }
}

private actor R117NativeWorker {
    static let shared = R117NativeWorker()
    private var pipelines: [URL: TermHintPipeline] = [:]

    func hints(
        text: String, resourceDirectory: URL, progress: ProtocolTermClient.Progress?
    ) async throws -> [TermHint] {
        try Task.checkCancellation()
        if pipelines[resourceDirectory] == nil {
            await progress?(.preparingExtraction)
            try Task.checkCancellation()
        }
        // 준비 콜백의 await 이후 캐시를 다시 확인해 중복 로딩을 피합니다.
        let pipeline: TermHintPipeline
        if let cached = pipelines[resourceDirectory] {
            pipeline = cached
        } else {
            let assets = resourceDirectory.appendingPathComponent("native-assets")
            let config = MLModelConfiguration()
            config.computeUnits = .cpuOnly
            pipeline = try TermHintPipeline(
                modelURL: assets.appendingPathComponent("sentencepiece.bpe.model"),
                modelPackageURL: resourceDirectory.appendingPathComponent("Unicode4.mlpackage"),
                charVocabURL: assets.appendingPathComponent("char_vocab.json"),
                configuration: config)
            pipelines[resourceDirectory] = pipeline
        }
        await progress?(.extractingCandidates)
        try Task.checkCancellation()
        // 추론과 decoder는 suspension 없이 실행하여 actor 재진입 시에도 겹치지 않습니다.
        let hints = try pipeline.hints(for: text)
        try Task.checkCancellation()
        return hints
    }
}

nonisolated enum R117NativeError: Error {
    case invalidPrediction
}
