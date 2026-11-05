import Foundation
import LabcordShared

@main
struct ContractChecks {
    static func main() throws {
        let experimentID = UUID()
        let date = Date(timeIntervalSince1970: 100)
        let start = WatchExperimentCommand(
            operation: .startTimer, experimentID: experimentID, durationSeconds: 60
        )
        let mutation = try WatchTimerMutation.prepare(start, timers: [], at: date)
        precondition(mutation.collection.timers[0].id == start.requestID)
        let duplicate = try WatchTimerMutation.prepare(
            start, timers: mutation.collection.timers, at: date + 1
        )
        precondition(duplicate.collection.timers == mutation.collection.timers)
        let pause = WatchExperimentCommand(
            operation: .pauseTimer, experimentID: experimentID, targetID: start.requestID
        )
        let paused = try WatchTimerMutation.prepare(
            pause, timers: mutation.collection.timers, at: date.addingTimeInterval(10)
        )
        precondition(paused.collection.timers[0].remainingSeconds(at: date + 100) == 50)
        let delete = WatchExperimentCommand(
            operation: .deleteTimer, experimentID: experimentID, targetID: start.requestID
        )
        let deleted = try WatchTimerMutation.prepare(
            delete, timers: mutation.collection.timers, at: date + 20
        )
        precondition(deleted.collection.timers.isEmpty && deleted.changes[0].endedAt == date + 20)
        try checkTimerLimits(start: start, date: date)
        try checkResponseCompatibility()
        print("PASS: timer mutation, limits, clock correction and response codec")
    }

    static func checkTimerLimits(start: WatchExperimentCommand, date: Date) throws {
        let full = (0..<5).map { _ in
            ExperimentTimer(durationSeconds: 10, startedAt: date)
        }
        do {
            _ = try WatchTimerMutation.prepare(start, timers: full, at: date)
            fatalError("sixth timer was accepted")
        } catch WatchExperimentError.invalidPayload {}
        let invalid = WatchExperimentCommand(operation: .startTimer, durationSeconds: -1)
        do {
            _ = try WatchTimerMutation.prepare(invalid, timers: [], at: date)
            fatalError("negative duration was accepted")
        } catch WatchExperimentError.invalidPayload {}
        let running = WatchTimerSnapshot(
            id: UUID(), durationSeconds: 60, remainingSeconds: 50,
            status: .running, measuredAt: date
        )
        precondition(running.remaining(at: date + 20) == 30)
        precondition(running.remaining(at: date + 70) == 0)
    }

    static func checkResponseCompatibility() throws {
        let id = UUID()
        let legacy = Data("{\"version\":1,\"requestID\":\"\(id)\",\"phase\":\"completed\"}".utf8)
        let response = try JSONDecoder().decode(WatchExperimentResponse.self, from: legacy)
        precondition(response.record == nil && response.requestID == id)
        let saved = WatchExperimentResponse(
            requestID: id, phase: .completed,
            record: WatchRecordSnapshot(id: id, kind: .photo, phase: .saved)
        )
        let decoded = try JSONDecoder().decode(
            WatchExperimentResponse.self, from: JSONEncoder().encode(saved)
        )
        precondition(decoded == saved)
    }
}
