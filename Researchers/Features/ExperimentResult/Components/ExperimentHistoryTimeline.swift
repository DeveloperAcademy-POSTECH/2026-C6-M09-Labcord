import LabcordDesignSystem
import LabcordiOS
import LabcordShared
import SwiftUI

struct ExperimentHistoryTimeline: View {
    let detail: ExperimentResultDetail
    let records: [ExperimentResultDetail.Record]
    let includesStatus: Bool
    let newestFirst: Bool
    @State private var activeMediaID: UUID?

    private var events: [HistoryEvent] {
        var events = records.map(HistoryEvent.record)
        if includesStatus {
            events += detail.statusHistory.enumerated().map { index, entry in
                .status(entry, isFirst: index == 0)
            }
        }
        return events.sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return newestFirst ? $0.date > $1.date : $0.date < $1.date
        }
    }

    private var days: [Date] {
        var seen = Set<Date>()
        return events.compactMap {
            let day = ExperimentHistoryDateFormatter.calendar.startOfDay(for: $0.date)
            return seen.insert(day).inserted ? day : nil
        }
    }

    var body: some View {
        if events.isEmpty {
            Text("표시할 기록이 없어요.")
                .typography(Typography.body)
                .foregroundStyle(Color("General/Label/Secondary",
                                       bundle: LabcordDesignSystemResources.bundle))
                .frame(maxWidth: .infinity)
                .padding(LayoutTokens.spacing24)
        } else {
            LazyVStack(alignment: .leading, spacing: LayoutTokens.spacing16) {
                ForEach(days, id: \.self) { day in
                    Text(ExperimentResultDateFormatter.date(day))
                        .typography(Typography.calloutSemiBold)
                        .padding(.horizontal, LayoutTokens.spacing16)
                    ForEach(events.filter {
                        ExperimentHistoryDateFormatter.calendar.isDate($0.date, inSameDayAs: day)
                    }) { event in
                        eventView(event)
                    }
                }
            }
            .accessibilityIdentifier("experiment-history-timeline")
        }
    }

    @ViewBuilder
    private func eventView(_ event: HistoryEvent) -> some View {
        switch event {
        case let .record(record):
            ExperimentHistoryRecordView(record: record, activeMediaID: $activeMediaID)
        case let .status(entry, isFirst):
            TimelineExperimentState(
                statusTitle(entry, isFirst: isFirst),
                timestamp: ExperimentHistoryDateFormatter.time(entry.date)
            )
        }
    }

    private func statusTitle(
        _ entry: ExperimentResultDetail.StatusEntry, isFirst: Bool
    ) -> String {
        switch entry.status {
        case .ready: "실험 준비"
        case .running: isFirst ? "실험 시작" : "실험 재개"
        case .paused: "실험 일시정지"
        case .completed: "실험 종료"
        }
    }
}

enum ExperimentHistoryDateFormatter {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return calendar
    }()

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func time(_ date: Date) -> String {
        clock.string(from: date)
    }
}

private enum HistoryEvent: Identifiable {
    case record(ExperimentResultDetail.Record)
    case status(ExperimentResultDetail.StatusEntry, isFirst: Bool)

    var id: String {
        switch self {
        case let .record(record): "record-\(record.id)"
        case let .status(entry, _): "status-\(entry.id)"
        }
    }

    var date: Date {
        switch self {
        case let .record(record): record.recordedAt
        case let .status(entry, _): entry.date
        }
    }
}
