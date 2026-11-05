import CoreML
import Foundation

actor NativeTermCandidateGenerator {
    private let resourceDirectory: URL

    init(resourceDirectory: URL) {
        self.resourceDirectory = resourceDirectory
    }

    func hints(
        text: String, progress: ProtocolTermClient.Progress?
    ) async throws -> [TermHint] {
        try await NativeTermWorker.shared.hints(
            text: text, resourceDirectory: resourceDirectory, progress: progress)
    }
}

private actor NativeTermWorker {
    static let shared = NativeTermWorker()
    private var pipelines: [URL: TermHintPipeline] = [:]

    func hints(
        text: String, resourceDirectory: URL, progress: ProtocolTermClient.Progress?
    ) async throws -> [TermHint] {
        try Task.checkCancellation()
        if pipelines[resourceDirectory] == nil {
            await progress?(.preparingExtraction)
            try Task.checkCancellation()
        }

        let pipeline: TermHintPipeline
        if let cached = pipelines[resourceDirectory] {
            pipeline = cached
        } else {
            let tokenizerAssets = resourceDirectory.appendingPathComponent("native-assets")
            let modelConfiguration = MLModelConfiguration()
            modelConfiguration.computeUnits = .cpuOnly
            pipeline = try TermHintPipeline(
                modelURL: tokenizerAssets.appendingPathComponent("sentencepiece.bpe.model"),
                modelPackageURL: resourceDirectory.appendingPathComponent("Unicode4.mlpackage"),
                charVocabURL: tokenizerAssets.appendingPathComponent("char_vocab.json"),
                configuration: modelConfiguration)
            pipelines[resourceDirectory] = pipeline
        }
        await progress?(.extractingCandidates)
        try Task.checkCancellation()

        let hints = try pipeline.hints(for: text)
        try Task.checkCancellation()
        return hints
    }
}

nonisolated public enum NativeTermError: LocalizedError {
    case tokenizerLoadFailed
    case invalidCharacterVocabulary
    case invalidPrediction

    public var errorDescription: String? {
        switch self {
        case .tokenizerLoadFailed: "토크나이저를 불러오지 못했습니다."
        case .invalidCharacterVocabulary: "문자 어휘 파일의 형식이 올바르지 않습니다."
        case .invalidPrediction: "모델의 추론 결과가 올바르지 않습니다."
        }
    }
}
