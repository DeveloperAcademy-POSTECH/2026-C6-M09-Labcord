import CoreML
import Foundation

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

nonisolated enum R117NativeError: Error {
    case invalidPrediction
}
