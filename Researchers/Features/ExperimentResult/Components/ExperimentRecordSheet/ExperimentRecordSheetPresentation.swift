import Foundation
import LabcordDesignSystem
import LabcordiOS
import LabcordShared

struct ExperimentRecordSheetPresentation {
    struct TimerDetails {
        let setDuration: String
        let state: TimerRecordState
        let elapsedTime: String
        let cumulativeTime: String
        let pauseCount: String

        init(
            record: ExperimentResultDetail.Record,
            event: ExperimentResultDetail.TimelineTimerEvent,
            date: Date
        ) {
            state = switch event {
            case .start: .start
            case .paused: .paused
            case .resumed: .resume
            case .ended: .end
            }

            let pauses = record.timerPauses.filter { $0.pausedAt <= date }
            let lastResumedAt = record.timerPauses.compactMap(\.resumedAt)
                .filter { $0 <= date }
                .max() ?? record.recordedAt
            let elapsedSeconds = max(0, Int(date.timeIntervalSince(lastResumedAt)))
            let pausedDuration = pauses.reduce(0.0) { total, pause in
                let resumedAt = min(pause.resumedAt ?? date, date)
                return total + max(0, resumedAt.timeIntervalSince(pause.pausedAt))
            }
            let cumulativeSeconds = max(
                0,
                Int(date.timeIntervalSince(record.recordedAt) - pausedDuration)
            )

            setDuration = record.timerDurationSeconds.map {
                TimerDurationFormatter.string(from: $0)
            } ?? "타이머"
            elapsedTime = "\(TimerDurationFormatter.string(from: elapsedSeconds)) 실행"
            cumulativeTime = TimerDurationFormatter.string(from: cumulativeSeconds)
            pauseCount = "(\(pauses.count))"
        }
    }

    let record: ExperimentResultDetail.Record
    let timer: TimerDetails?

    init?(entry: ExperimentResultDetail.TimelineEntry) {
        switch entry.kind {
        case let .record(record):
            self.record = record
            timer = record.type == .timer
                ? TimerDetails(record: record, event: .start, date: entry.date) : nil
        case let .timer(record, event):
            self.record = record
            timer = TimerDetails(record: record, event: event, date: entry.date)
        case .status, .started, .ended, .paused, .resumed:
            return nil
        }
    }

    var type: LabcordDesignSystem.RecordType {
        switch record.type {
        case .photo: .photo
        case .video: .video
        case .audio: .voice
        case .timer: .timer
        }
    }

    var mediaURL: URL? {
        guard let filePath = record.filePath else { return nil }
        let url = URL.applicationSupportDirectory.appending(path: filePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
