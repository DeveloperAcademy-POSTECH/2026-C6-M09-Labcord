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
            RecordedTimerTimelineView(
                record: record,
                event: event,
                timestamp: timestamp,
                date: entry.date
            )
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
            photoRecord(record, timestamp: timestamp)
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
            RecordedTimerTimelineView(
                record: record,
                event: .start,
                timestamp: timestamp,
                date: record.recordedAt
            )
        }
    }

    private func photoRecord(
        _ record: ExperimentResultDetail.Record,
        timestamp: String
    ) -> some View {
        let image = mediaURL(for: record).flatMap { UIImage(contentsOfFile: $0.path) }
        let photoAspectRatio = image.map {
            $0.size.height > $0.size.width ? 3.0 / 4.0 : 16.0 / 9.0
        } ?? 16.0 / 9.0

        return TimelineItem(
            timestamp: timestamp,
            title: "사진 기록",
            memo: record.note,
            showMemo: !record.note.isEmpty,
            type: .photo,
            photoAspectRatio: photoAspectRatio
        ) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text("사진 파일을 불러올 수 없습니다.")
            }
        }
    }

    private func mediaURL(for record: ExperimentResultDetail.Record) -> URL? {
        guard let filePath = record.filePath else { return nil }
        let url = URL.applicationSupportDirectory.appending(path: filePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
