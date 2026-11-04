import Foundation

nonisolated struct ProtocolAnalysisProgress {
    let completed: Int64
    let total: Int64
    let subtitle: String

    static func values(
        record: ProtocolAnalysisJobRecord, phase: ProtocolAnalysisJobPhase
    ) -> Self {
        let total = Int64(record.inputs.count * 3_000)
        var completed = Int64(
            record.documents.count + record.selected.count + record.finished.count
        ) * 1_000
        let subtitle: String
        switch phase {
        case .queued: subtitle = "분석 시작을 기다리고 있어요"
        case .reading: subtitle = "문서에서 본문을 읽고 있어요"
        case let .terms(_, value):
            if case let .classifyingTerms(done, count) = value {
                subtitle = "용어 분류 \(done)/\(count)개"
                completed += Int64(done * 1_000 / max(1, count))
            } else if case let .rankingProgress(done, count) = value {
                subtitle = "용어 문맥 검토 \(done)/\(count)개"
                completed += Int64(done * 1_000 / max(1, count))
            } else {
                subtitle = "타이머와 용어를 찾고 있어요"
            }
        }
        return Self(completed: completed, total: total, subtitle: subtitle)
    }
}
