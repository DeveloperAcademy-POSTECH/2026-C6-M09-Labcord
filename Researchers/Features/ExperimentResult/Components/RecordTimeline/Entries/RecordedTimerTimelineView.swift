import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct RecordedTimerTimelineView: View {
    let record: ExperimentResultDetail.Record
    let event: ExperimentResultDetail.TimelineEntry.TimerEvent
    let timestamp: String
    let date: Date

    var body: some View {
        let state: TimerRecordState = switch event {
        case .start: .start
        case .paused: .paused
        case .resumed: .resume
        case .ended: .end
        }
        let pauseCount = record.timerPauses.filter { $0.pausedAt <= date }.count
        let lastResumedAt = record.timerPauses.compactMap(\.resumedAt)
            .filter { $0 <= date }
            .max() ?? record.recordedAt
        let elapsedSeconds = max(0, Int(date.timeIntervalSince(lastResumedAt)))
        let pausedDuration = record.timerPauses.reduce(0.0) { total, pause in
            guard pause.pausedAt < date else { return total }
            let resumedAt = min(pause.resumedAt ?? date, date)
            return total + max(0, resumedAt.timeIntervalSince(pause.pausedAt))
        }
        let cumulativeSeconds = max(
            0,
            Int(date.timeIntervalSince(record.recordedAt) - pausedDuration)
        )

        TimelineItem(
            timestamp: timestamp,
            title: "타이머 기록",
            memo: record.note,
            showMemo: !record.note.isEmpty,
            type: .timer
        ) {
            TimerRecord(
                setDuration: record.timerDurationSeconds.map { "\($0)초" } ?? "타이머",
                elapsedTime: "\(elapsedSeconds)초 실행",
                cumulativeTime: "\(cumulativeSeconds)초",
                pauseCount: "(\(pauseCount))",
                state: state
            )
        }
    }
}
