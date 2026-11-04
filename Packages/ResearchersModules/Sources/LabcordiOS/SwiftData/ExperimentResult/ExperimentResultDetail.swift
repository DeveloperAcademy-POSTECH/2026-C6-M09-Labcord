import Foundation
import LabcordShared

public struct ExperimentResultDetail: Equatable, Sendable {
    public enum TimelineTimerEvent: Equatable, Sendable {
        case start
        case paused
        case resumed
        case ended
    }

    public enum TimelineKind: Equatable, Sendable {
        case status(ExperimentStatus)
        case started
        case ended
        case paused
        case resumed
        case record(Record)
        case timer(Record, TimelineTimerEvent)
    }

    public struct TimelineEntry: Equatable, Sendable, Identifiable {
        public let id: String
        public let date: Date
        public let kind: TimelineKind
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
        let statusEvents: [TimelineEntry] =
            statusHistory.enumerated().compactMap { index, entry in
                switch entry.status {
                case .ready:
                    TimelineEntry(
                        id: "status-\(entry.id)", date: entry.date, kind: .status(.ready)
                    )
                case .paused:
                    TimelineEntry(id: "status-\(entry.id)", date: entry.date, kind: .paused)
                case .running where index > 0 && statusHistory[index - 1].status == .paused:
                    TimelineEntry(id: "status-\(entry.id)", date: entry.date, kind: .resumed)
                case .running, .completed:
                    nil
                }
            }

        let pauseEvents: [TimelineEntry] =
            pauses.flatMap { pause in
                var events: [TimelineEntry] = []
                if !statusHistory.contains(where: {
                    $0.status == .paused && $0.date == pause.pausedAt
                }) {
                    events.append(
                        TimelineEntry(id: "pause-\(pause.id)", date: pause.pausedAt, kind: .paused)
                    )
                }
                if let resumedAt = pause.resumedAt,
                   !statusHistory.contains(where: {
                       $0.status == .running && $0.date == resumedAt
                   }) {
                    events.append(
                        TimelineEntry(id: "resume-\(pause.id)", date: resumedAt, kind: .resumed)
                    )
                }
                return events
            }

        let recordEvents: [TimelineEntry] =
            records.flatMap { record -> [TimelineEntry] in
                guard record.type == .timer else {
                    return [TimelineEntry(
                        id: "record-\(record.id)",
                        date: record.recordedAt,
                        kind: .record(record)
                    )]
                }

                var events: [TimelineEntry] = [
                    TimelineEntry(
                        id: "timer-start-\(record.id)",
                        date: record.recordedAt,
                        kind: .timer(record, .start)
                    )
                ]
                for pause in record.timerPauses {
                    events.append(
                        TimelineEntry(
                            id: "timer-pause-\(pause.id)",
                            date: pause.pausedAt,
                            kind: .timer(record, .paused)
                        )
                    )
                    if let resumedAt = pause.resumedAt {
                        events.append(
                            TimelineEntry(
                                id: "timer-resume-\(pause.id)",
                                date: resumedAt,
                                kind: .timer(record, .resumed)
                            )
                        )
                    }
                }
                if let timerEndedAt = record.timerEndedAt {
                    let hasOpenPause = record.timerPauses.contains {
                        $0.pausedAt <= timerEndedAt && $0.resumedAt == nil
                    }
                    if !hasOpenPause || endedAt.contains(timerEndedAt) {
                        events.append(
                            TimelineEntry(
                                id: "timer-end-\(record.id)",
                                date: timerEndedAt,
                                kind: .timer(record, .ended)
                            )
                        )
                    }
                }
                return events
            }

        let events: [TimelineEntry] =
            statusEvents
            + (startedAt.map { [TimelineEntry(id: "started", date: $0, kind: .started)] } ?? [])
            + (endedAt.last.map { [TimelineEntry(id: "ended", date: $0, kind: .ended)] } ?? [])
            + pauseEvents
            + recordEvents

        return events.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.kind == .status(.ready) { return true }
            if $1.kind == .status(.ready) { return false }
            return $0.id < $1.id
        }
    }
}
