import Foundation

nonisolated struct ProtocolAnalysisProgress {
    let completed: Int64
    let total: Int64
    let subtitle: String

    private enum Stage: CaseIterable {
        case document, selection, classification

        static let units: Int64 = 1_000

        func completedCount(in record: ProtocolAnalysisJobRecord) -> Int {
            switch self {
            case .document: record.documents.count
            case .selection: record.selected.count
            case .classification: record.finished.count
            }
        }

        func isActive(for key: String, in record: ProtocolAnalysisJobRecord) -> Bool {
            switch self {
            case .document: record.documents[key] == nil
            case .selection: record.documents[key] != nil && record.selected[key] == nil
            case .classification: record.selected[key] != nil && !record.finished.contains(key)
            }
        }

        func units(completed: Int, total: Int) -> Int64 {
            Int64(min(max(completed, 0), max(total, 0))) * Self.units / Int64(max(1, total))
        }
    }

    static func values(
        record: ProtocolAnalysisJobRecord, phase: ProtocolAnalysisJobPhase
    ) -> Self {
        let total = Int64(record.inputs.count * Stage.allCases.count) * Stage.units
        var completed = Int64(Stage.allCases.reduce(0) { $0 + $1.completedCount(in: record) })
            * Stage.units
        let subtitle: String
        switch phase {
        case .queued: subtitle = "분석 시작을 기다리고 있어요"
        case .reading: subtitle = "문서에서 본문을 읽고 있어요"
        case let .terms(inputID, value):
            let key = inputID.uuidString
            if case let .classifyingTerms(done, count) = value {
                subtitle = "용어 분류 \(done)/\(count)개"
                if Stage.classification.isActive(for: key, in: record) {
                    completed += Stage.classification.units(completed: done, total: count)
                }
            } else if case let .rankingProgress(done, count) = value {
                subtitle = "용어 문맥 검토 \(done)/\(count)개"
                if Stage.selection.isActive(for: key, in: record) {
                    completed += Stage.selection.units(completed: done, total: count)
                }
            } else if case .organizingTerms = value,
                      Stage.classification.isActive(for: key, in: record) {
                subtitle = "타이머와 용어를 정리하고 있어요"
                completed += Stage.units
            } else {
                subtitle = "타이머와 용어를 찾고 있어요"
            }
        }
        return Self(completed: completed, total: total, subtitle: subtitle)
    }
}
