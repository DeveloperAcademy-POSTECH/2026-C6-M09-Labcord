import Foundation

nonisolated enum ProtocolAnalysisSystemProgress {
    static func update(record: ProtocolAnalysisJobRecord, phase: ProtocolAnalysisJobPhase) async {
        let progress = ProtocolAnalysisProgress.values(record: record, phase: phase)
        await ProtocolAnalysisBackgroundScheduler.shared.update(
            id: record.id, completed: min(progress.total, progress.completed),
            total: progress.total, subtitle: progress.subtitle
        )
    }
}
