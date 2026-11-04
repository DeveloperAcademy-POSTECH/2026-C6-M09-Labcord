import Foundation
import LabcordShared

public struct ExperimentResultDetail: Equatable, Sendable {
    public struct TimelineEntry: Equatable, Sendable, Identifiable {
        public enum TimerEvent: Equatable, Sendable {
            case start
            case paused
            case resumed
            case ended
        }

        public enum Kind: Equatable, Sendable {
            case status(ExperimentStatus)
            case started
            case ended
            case paused
            case resumed
            case record(Record)
            case timer(Record, TimerEvent)
        }

        public let id: String
        public let date: Date
        public let kind: Kind
    }

    public struct Procedure: Equatable, Sendable {
        public let timerSeconds: [Int]
        public let materials: [String]
        public let samples: [String]
        public let glossaryTerms: [String]
        public let units: [String]
    }

    public struct PauseEntry: Equatable, Sendable {
        public let id: UUID
        public let pausedAt: Date
        public let resumedAt: Date?
    }

    public struct Record: Equatable, Sendable {
        public let id: UUID
        public let type: RecordType
        public let recordedAt: Date
        public let note: String
        public let filePath: String?
        public let transcript: String?
        public let timerDurationSeconds: Int?
        public let timerEndedAt: Date?
        public let timerPauses: [PauseEntry]
    }

    public struct StatusEntry: Equatable, Sendable {
        public let id: UUID
        public let status: ExperimentStatus
        public let date: Date
    }

    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let startedAt: Date?
    public let endedAt: [Date]
    public let status: ExperimentStatus
    public let mode: ExperimentMode
    public let procedure: Procedure?
    public let pauses: [PauseEntry]
    public let records: [Record]
    public let statusHistory: [StatusEntry]

    public var timeline: [TimelineEntry] {
        let statusEvents: [(id: String, date: Date, kind: TimelineEntry.Kind)] =
            statusHistory.enumerated().compactMap { index, entry in
                switch entry.status {
                case .ready:
                    ("status-\(entry.id)", entry.date, .status(.ready))
                case .paused:
                    ("status-\(entry.id)", entry.date, .paused)
                case .running where index > 0 && statusHistory[index - 1].status == .paused:
                    ("status-\(entry.id)", entry.date, .resumed)
                case .running, .completed:
                    nil
                }
            }

        let pauseEvents: [(id: String, date: Date, kind: TimelineEntry.Kind)] =
            pauses.flatMap { pause in
                var events: [(id: String, date: Date, kind: TimelineEntry.Kind)] = []
                if !statusHistory.contains(where: {
                    $0.status == .paused && $0.date == pause.pausedAt
                }) {
                    events.append(("pause-\(pause.id)", pause.pausedAt, .paused))
                }
                if let resumedAt = pause.resumedAt,
                   !statusHistory.contains(where: {
                       $0.status == .running && $0.date == resumedAt
                   }) {
                    events.append(("resume-\(pause.id)", resumedAt, .resumed))
                }
                return events
            }

        let recordEvents: [(id: String, date: Date, kind: TimelineEntry.Kind)] =
            records.flatMap { record -> [(id: String, date: Date, kind: TimelineEntry.Kind)] in
                guard record.type == .timer else {
                    return [("record-\(record.id)", record.recordedAt, .record(record))]
                }

                var events: [(id: String, date: Date, kind: TimelineEntry.Kind)] = [
                    ("timer-start-\(record.id)", record.recordedAt, .timer(record, .start))
                ]
                for pause in record.timerPauses {
                    events.append(
                        ("timer-pause-\(pause.id)", pause.pausedAt, .timer(record, .paused))
                    )
                    if let resumedAt = pause.resumedAt {
                        events.append(
                            ("timer-resume-\(pause.id)", resumedAt, .timer(record, .resumed))
                        )
                    }
                }
                if let timerEndedAt = record.timerEndedAt {
                    let hasOpenPause = record.timerPauses.contains {
                        $0.pausedAt <= timerEndedAt && $0.resumedAt == nil
                    }
                    if !hasOpenPause || endedAt.contains(timerEndedAt) {
                        events.append(
                            ("timer-end-\(record.id)", timerEndedAt, .timer(record, .ended))
                        )
                    }
                }
                return events
            }

        let datesAndKinds: [(id: String, date: Date, kind: TimelineEntry.Kind)] =
            statusEvents
            + (startedAt.map { [("started", $0, .started)] } ?? [])
            + (endedAt.last.map { [("ended", $0, .ended)] } ?? [])
            + pauseEvents
            + recordEvents

        return datesAndKinds.map { entry in
            TimelineEntry(
                id: entry.id,
                date: entry.date,
                kind: entry.kind
            )
        }
        .sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.kind == .status(.ready) { return true }
            if $1.kind == .status(.ready) { return false }
            return $0.id < $1.id
        }
    }
}
