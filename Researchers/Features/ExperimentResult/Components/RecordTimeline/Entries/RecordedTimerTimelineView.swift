import LabcordDesignSystem
import LabcordiOS
import LabcordShared
import SwiftUI

struct RecordedTimerTimelineView: View {
    let record: ExperimentResultDetail.Record
    let event: ExperimentResultDetail.TimelineTimerEvent
    let timestamp: String
    let date: Date
    let note: String

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
            memo: note,
            showMemo: !note.isEmpty,
            type: .timer
        ) {
            TimerRecord(
                setDuration: record.timerDurationSeconds.map {
                    TimerDurationFormatter.string(from: $0)
                } ?? "타이머",
                elapsedTime: "\(TimerDurationFormatter.string(from: elapsedSeconds)) 실행",
                cumulativeTime: TimerDurationFormatter.string(from: cumulativeSeconds),
                pauseCount: "(\(pauseCount))",
                state: state
            )
        }
    }
}
