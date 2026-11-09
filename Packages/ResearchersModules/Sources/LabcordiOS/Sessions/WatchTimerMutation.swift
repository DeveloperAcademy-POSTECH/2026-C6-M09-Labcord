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
        if let existing = collection.timers.first(where: { $0.id == command.requestID }) {
            guard existing.durationSeconds == seconds else {
                throw WatchExperimentError.duplicateConflict
            }
            return
        }
        guard collection.start(
            id: command.requestID, durationSeconds: seconds, at: date
        ) else {
            throw WatchExperimentError.invalidPayload
        }
    }

}
