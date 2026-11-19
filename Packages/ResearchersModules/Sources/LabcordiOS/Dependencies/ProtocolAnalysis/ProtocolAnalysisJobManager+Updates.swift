import Foundation
import OSLog

extension ProtocolAnalysisJobManager {
    func logAnalysisFailure(
        _ error: Error, record: ProtocolAnalysisJobRecord?, phase: ProtocolAnalysisJobPhase
    ) {
        let failure = error as NSError
        let stage = record.map {
            ProtocolAnalysisProgress.values(record: $0, phase: phase).subtitle
        } ?? "unknown"
        Logger(subsystem: "com.labcord", category: "ProtocolAnalysis").error(
            """
            Analysis failed: domain=\(failure.domain, privacy: .public) \
            code=\(failure.code) stage=\(stage, privacy: .public)
            """
        )
    }

    public func updates() -> AsyncStream<ProtocolAnalysisJobSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ProtocolAnalysisJobSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        listeners[id] = continuation
        if let value = try? snapshot() { continuation.yield(value) }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeListener(id) }
        }
        return stream
    }

    private func removeListener(_ id: UUID) { listeners[id] = nil }
}
