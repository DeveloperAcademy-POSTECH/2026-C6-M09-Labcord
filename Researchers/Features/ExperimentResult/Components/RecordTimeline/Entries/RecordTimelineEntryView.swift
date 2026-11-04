import LabcordDesignSystem
import LabcordiOS
import LabcordShared
import SwiftUI

struct RecordTimelineEntryView: View {
    let entry: ExperimentResultDetail.TimelineEntry

    var body: some View {
        timelineRow(entry)
    }

    @ViewBuilder
    private func timelineRow(_ entry: ExperimentResultDetail.TimelineEntry) -> some View {
        let timestamp = ExperimentResultDateFormatter.time(entry.date)

        switch entry.kind {
        case .status:
            EmptyView()
        case .started:
            TimelineExperimentState("실험 시작", timestamp: timestamp)
        case .ended:
            TimelineExperimentState("실험 종료", timestamp: timestamp)
        case .paused:
            TimelineExperimentState("실험 일시 중지", timestamp: timestamp)
        case .resumed:
            TimelineExperimentState("실험 재개", timestamp: timestamp)
        case let .record(record):
            timelineRecord(record, timestamp: timestamp)
        case let .timer(record, event):
            timelineTimer(record, event: event, timestamp: timestamp, date: entry.date)
        }
    }

    @ViewBuilder
    private func timelineRecord(
        _ record: ExperimentResultDetail.Record,
        timestamp: String
    ) -> some View {
        switch record.type {
        case .audio:
            TimelineItem(
                timestamp: timestamp,
                title: record.transcript ?? "음성 기록",
                memo: record.note,
                showMemo: !record.note.isEmpty,
                type: .voice
            ) {
                if let url = mediaURL(for: record) {
                    RecordedAudioTimelineView(url: url)
                } else {
                    Text("음성 파일을 불러올 수 없습니다.")
                }
            }
        case .photo:
            TimelineItem(
                timestamp: timestamp,
                title: "사진 기록",
                memo: record.note,
                showMemo: !record.note.isEmpty,
                type: .photo
            ) {
                if let url = mediaURL(for: record),
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text("사진 파일을 불러올 수 없습니다.")
                }
            }
        case .video:
            TimelineItem(
                timestamp: timestamp,
                title: "영상 기록",
                memo: record.note,
                showMemo: !record.note.isEmpty,
                type: .video
            ) {
                if let url = mediaURL(for: record) {
                    RecordedVideoTimelineView(url: url)
                } else {
                    Text("영상 파일을 불러올 수 없습니다.")
                }
            }
        case .timer:
            timelineTimer(record, event: .start, timestamp: timestamp, date: record.recordedAt)
        }
    }

    private func timelineTimer(
        _ record: ExperimentResultDetail.Record,
        event: ExperimentResultDetail.TimelineEntry.TimerEvent,
        timestamp: String,
        date: Date
    ) -> some View {
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

        return TimelineItem(
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

    private func mediaURL(for record: ExperimentResultDetail.Record) -> URL? {
        guard let filePath = record.filePath else { return nil }
        let url = URL.applicationSupportDirectory.appending(path: filePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
