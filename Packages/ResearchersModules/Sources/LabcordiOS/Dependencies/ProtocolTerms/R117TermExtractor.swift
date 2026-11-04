import Foundation
import OSLog

nonisolated public final class R117TermExtractor: Sendable {
    public static let shared = R117TermExtractor()
    static var resourceDirectory: URL? {
        Bundle.module.url(forResource: "R117", withExtension: nil)
    }
    private let extractionRuntime = R117ExtractionRuntime()

    public func extract(
        from text: String, progress: ProtocolTermClient.Progress? = nil
    ) async throws -> [String] {
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return try await extractionRuntime.extract(text, progress: progress)
    }
}

nonisolated public enum R117ExtractionError: LocalizedError, Sendable {
    case resourcesUnavailable

    public var errorDescription: String? {
        "용어 추출 기능을 사용할 수 없어요. 용어를 직접 입력해 주세요."
    }
}

private actor R117ExtractionRuntime {
    private var candidateGenerator: R117NativeCandidateGenerator?
    private let logger = Logger(subsystem: "com.labcord", category: "R117")

    func extract(
        _ text: String, progress: ProtocolTermClient.Progress?
    ) async throws -> [String] {
        let extractionClock = ContinuousClock()
        let extractionStarted = extractionClock.now
        defer {
            let elapsed = String(describing: extractionStarted.duration(to: extractionClock.now))
            logger.info("R117 extraction finished after \(elapsed, privacy: .public)")
        }
        try Task.checkCancellation()
        guard let resourceDirectory = R117TermExtractor.resourceDirectory else {
            throw R117ExtractionError.resourcesUnavailable
        }
        let candidateGenerator: R117NativeCandidateGenerator
        if let cachedGenerator = self.candidateGenerator {
            candidateGenerator = cachedGenerator
        } else {
            candidateGenerator = R117NativeCandidateGenerator(resourceDirectory: resourceDirectory)
            self.candidateGenerator = candidateGenerator
        }
        let hints = try await candidateGenerator.hints(text: text, progress: progress)
        try Task.checkCancellation()
        return hints.map(\.text)
    }
}
