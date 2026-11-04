import Foundation
import OSLog

/// Unicode4 모델의 BIO span에서 원문 용어를 최대 50개 추출합니다.
nonisolated public final class R117TermExtractor: Sendable {
    public static let shared = R117TermExtractor()
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
        let hints = try await generator.hints(text: text, progress: progress)
        try Task.checkCancellation()
        return hints.map(\.text)
    }
}
