import Foundation
import OSLog

nonisolated public final class ProtocolTermExtractor: Sendable {
    public static let shared = ProtocolTermExtractor()
    static var resourceDirectory: URL? {
        Bundle.module.url(forResource: "ProtocolTermModel", withExtension: nil)
    }
    private let extractionRuntime = ProtocolTermExtractionRuntime()

    public func extract(
        from text: String, progress: ProtocolTermClient.Progress? = nil
    ) async throws -> [String] {
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return try await extractionRuntime.extract(text, progress: progress)
    }
}

nonisolated public enum ProtocolTermExtractionError: LocalizedError, Sendable {
    case resourcesUnavailable

    public var errorDescription: String? {
        "용어 추출 기능을 사용할 수 없어요. 용어를 직접 입력해 주세요."
    }
}

private actor ProtocolTermExtractionRuntime {
    private var candidateGenerator: NativeTermCandidateGenerator?
    private let logger = Logger(subsystem: "com.labcord", category: "ProtocolTerms")

    func extract(
        _ text: String, progress: ProtocolTermClient.Progress?
    ) async throws -> [String] {
        let extractionClock = ContinuousClock()
        let extractionStarted = extractionClock.now
        defer {
            let elapsed = String(describing: extractionStarted.duration(to: extractionClock.now))
            logger.info("Term extraction finished after \(elapsed, privacy: .public)")
        }
        try Task.checkCancellation()
        guard let resourceDirectory = ProtocolTermExtractor.resourceDirectory else {
            throw ProtocolTermExtractionError.resourcesUnavailable
        }
        let candidateGenerator: NativeTermCandidateGenerator
        if let cachedGenerator = self.candidateGenerator {
            candidateGenerator = cachedGenerator
        } else {
            candidateGenerator = NativeTermCandidateGenerator(resourceDirectory: resourceDirectory)
            self.candidateGenerator = candidateGenerator
        }
        let hints = try await candidateGenerator.hints(text: text, progress: progress)
        try Task.checkCancellation()
        return hints.map(\.text)
    }
}
