import Foundation
import LabcordShared

public struct WatchTimerMutation: Equatable, Sendable {
    public struct Change: Equatable, Sendable {
        public let timer: ExperimentTimer
        public let endedAt: Date?
    }

    public let collection: ExperimentTimerCollection
    public let changes: [Change]

    public static func prepare(
        _ command: WatchExperimentCommand, timers: [ExperimentTimer], at date: Date
    ) throws -> WatchTimerMutation {
        var collection = ExperimentTimerCollection(timers: timers, currentTime: date)
        collection.advance(to: date)
        var deleted: ExperimentTimer?
        switch command.operation {
        case .startTimer:
            try start(command, collection: &collection, at: date)
        case .pauseTimer:
            guard let id = command.targetID, collection.pause(id: id, at: date) else {
                throw WatchExperimentError.invalidState
            }
        case .resumeTimer:
            guard let id = command.targetID, collection.resume(id: id, at: date) else {
                throw WatchExperimentError.invalidState
            }
        case .deleteTimer:
            guard let id = command.targetID,
                  let timer = collection.timers.first(where: { $0.id == id }) else {
                throw WatchExperimentError.invalidState
            }
            deleted = timer
            collection = ExperimentTimerCollection(
                timers: collection.timers.filter { $0.id != id }, currentTime: date
            )
        default:
            throw WatchExperimentError.invalidPayload
        }
        var changes = collection.timers.compactMap { timer -> Change? in
            guard timers.first(where: { $0.id == timer.id }) != timer else { return nil }
            return Change(timer: timer, endedAt: nil)
        }
        if let deleted { changes.append(Change(timer: deleted, endedAt: date)) }
        return WatchTimerMutation(collection: collection, changes: changes)
    }
    private static func start(
        _ command: WatchExperimentCommand,
        collection: inout ExperimentTimerCollection, at date: Date
    ) throws {
        guard let seconds = command.durationSeconds, seconds > 0, seconds <= Int(Int32.max) else {
            throw WatchExperimentError.invalidPayload
        }
        let timerID = command.targetID ?? command.requestID
        if let existing = collection.timers.first(where: { $0.id == timerID }) {
            guard existing.durationSeconds == seconds else {
                throw WatchExperimentError.duplicateConflict
            }
            return
        }
        let startedAt = command.timerStartedAt ?? date
        let pauses = command.timerPauseIntervals ?? []
        guard startedAt <= date, collection.canStartTimer,
              validPauses(pauses, startedAt: startedAt, at: date) else {
            throw WatchExperimentError.invalidPayload
        }
        let timer = ExperimentTimer(
            id: timerID, durationSeconds: seconds,
            startedAt: startedAt, pauseIntervals: pauses
        )
        collection = ExperimentTimerCollection(
            timers: collection.timers + [timer], currentTime: date
        )
        collection.advance(to: date)
    }

    private static func validPauses(
        _ pauses: [ExperimentTimer.PauseInterval], startedAt: Date, at date: Date
    ) -> Bool {
        var previousEnd = startedAt
        for (index, pause) in pauses.enumerated() {
            guard pause.pausedAt >= previousEnd, pause.pausedAt <= date else { return false }
            if let resumedAt = pause.resumedAt {
                guard resumedAt >= pause.pausedAt, resumedAt <= date else { return false }
                previousEnd = resumedAt
            } else {
                guard index == pauses.count - 1 else { return false }
            }
        }
        return true
    }
}
