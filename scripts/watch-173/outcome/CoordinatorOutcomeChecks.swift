import Foundation

enum WatchExperimentError: Error, Equatable {
    case storageFailed, resultUnknown, phoneBusy, invalidPayload, requestExpired
}
struct WatchExperimentCommand {
    enum Operation { case other, prepareStart, requestStatus, confirmRecord, cancelRecord }
    let requestID = UUID()
    var operation: Operation = .other
    var targetID: UUID?
    var experimentID: UUID?
}
struct WatchExperimentSnapshot {
    let experiment: Experiment
    struct Experiment { let id: UUID }
}
struct WatchRecordSnapshot: Equatable {
    enum Phase { case saved, cancelled }
    let id: UUID
    var phase: Phase = .saved
}
struct WatchExperimentResponse {
    enum Phase: Equatable { case received, processing, completed, failed, unknown }
    let requestID: UUID
    let phase: Phase
    var experiments: [Int]?
    var snapshot: WatchExperimentSnapshot?
    var error: WatchExperimentError?
    var startToken: UUID?
    var record: WatchRecordSnapshot?
    var queriedRequestID: UUID?
}
struct WatchExperimentRequestJournal {
    struct Entry {
        let command: WatchExperimentCommand
        var response: WatchExperimentResponse
    }
    var entries: [UUID: Entry] = [:]
    var shouldFail = false
    mutating func save(
        _ command: WatchExperimentCommand, response: WatchExperimentResponse
    ) throws {
        if shouldFail { throw WatchExperimentError.storageFailed }
        entries[command.requestID] = Entry(command: command, response: response)
    }
}

@MainActor
final class Coordinator {
    var requests: [UUID: WatchExperimentRequestJournal.Entry] = [:]
    var recordResults: [UUID: WatchRecordSnapshot] = [:]
    var completedExecutions: [UUID: WatchCompletedExecution] = [:]
    var tokens: [UUID: (UUID, ContinuousClock.Instant)] = [:]
    var journal: WatchExperimentRequestJournal? = .init()
    var validationFails = false
    var snapshotFails = false
    var forceUnknownMerge = false
    var forceMergedPhase: WatchExperimentResponse.Phase?
    var forcedUnknownRecord: WatchRecordSnapshot?
    var performThrowsAfterEffect = false
    var performed = 0
    var experimentID = UUID()
    var nextToken: UUID?
    func beginExecution(_ command: WatchExperimentCommand) throws {}
    func finishExecution(_ id: UUID) {}
    func validate(_ command: WatchExperimentCommand) throws -> WatchExperimentSnapshot {
        if validationFails { throw WatchExperimentError.phoneBusy }
        return WatchExperimentSnapshot(experiment: .init(id: experimentID))
    }
    func perform(
        _ command: WatchExperimentCommand, current: WatchExperimentSnapshot
    ) async throws -> UUID? {
        performed += 1
        if performThrowsAfterEffect { throw WatchExecutionUncertain() }
        return nextToken
    }
    func snapshot(_ id: UUID) throws -> WatchExperimentSnapshot {
        if snapshotFails { throw WatchExperimentError.storageFailed }
        return WatchExperimentSnapshot(experiment: .init(id: id))
    }
    func publish(_ snapshot: WatchExperimentSnapshot) {}
    func restoreSavedRecords(_ id: UUID) throws {}
    func latestMediaResult(_ command: WatchExperimentCommand, response: WatchExperimentResponse)
        -> WatchExperimentResponse {
        if [.unknown, .failed].contains(response.phase), let record = forcedUnknownRecord {
            return WatchExperimentResponse(
                requestID: response.requestID, phase: .completed, record: record
            )
        }
        guard response.phase == .completed else { return response }
        let phase = forceUnknownMerge ? .unknown : forceMergedPhase
        guard let phase else { return response }
        return WatchExperimentResponse(
            requestID: response.requestID, phase: phase, snapshot: response.snapshot,
            error: phase == .unknown ? .resultUnknown : nil,
            startToken: response.startToken, record: response.record
        )
    }
    func failure(_ command: WatchExperimentCommand, _ error: WatchExperimentError)
        -> WatchExperimentResponse {
        WatchExperimentResponse(requestID: command.requestID, phase: .failed, error: error)
    }
    func enqueue(_ command: WatchExperimentCommand) {
        requests[command.requestID] = .init(
            command: command, response: .init(requestID: command.requestID, phase: .received)
        )
    }
    // ACTUAL_UNKNOWN_OUTCOME
    // ACTUAL_CONSERVATIVE_MEDIA_RESULT
    // ACTUAL_REQUEST_STATUS
    // ACTUAL_EXECUTE
}

// ACTUAL_OUTCOME_RECOVERY

@main
struct Checks {
    @MainActor static func main() async {
        let server = Coordinator()
        await checkSnapshotRecovery(server)
        await checkJournalAndRestart(server)
        await checkTokens(server)
        await checkUnknownMergeRetainsEvidence()
        await checkNonterminalMergeRetainsEvidence()
        await checkPartialEffectRemainsUnknown()
        checkOppositeRecordOutcome()
    }

    @MainActor private static func checkSnapshotRecovery(_ server: Coordinator) async {
        let command = WatchExperimentCommand()
        let record = WatchRecordSnapshot(id: UUID())
        server.enqueue(command)
        server.recordResults[command.requestID] = record
        server.snapshotFails = true
        await server.execute(command)
        precondition(server.performed == 1)
        precondition(server.requests[command.requestID]?.response.phase == .unknown)
        let query = WatchExperimentCommand(operation: .requestStatus, targetID: command.requestID)
        precondition(server.requestStatus(query).phase == .unknown)
        server.snapshotFails = false
        let recovered = server.requestStatus(query)
        precondition(recovered.phase == .completed
                     && recovered.queriedRequestID == command.requestID)
        precondition(recovered.record == record && server.performed == 1)
        precondition(server.requestStatus(query).phase == .completed && server.performed == 1)
        print("PASS: post-execution snapshot recovery preserves result without re-execution")

        let rejected = WatchExperimentCommand()
        server.enqueue(rejected)
        server.validationFails = true
        await server.execute(rejected)
        precondition(server.performed == 1)
        precondition(server.requests[rejected.requestID]?.response.phase == .failed)
        precondition(server.requests[rejected.requestID]?.response.error == .phoneBusy)
        print("PASS: validation failure remains definitive and does not execute")
    }

    @MainActor private static func checkJournalAndRestart(_ server: Coordinator) async {
        let unjournaled = WatchExperimentCommand()
        server.enqueue(unjournaled)
        server.validationFails = false
        server.journal?.shouldFail = true
        await server.execute(unjournaled)
        precondition(server.performed == 2)
        precondition(server.requests[unjournaled.requestID]?.response.phase == .unknown)
        let retry = WatchExperimentCommand(
            operation: .requestStatus, targetID: unjournaled.requestID
        )
        precondition(server.requestStatus(retry).phase == .unknown)
        server.journal?.shouldFail = false
        precondition(server.requestStatus(retry).phase == .completed && server.performed == 2)
        print("PASS: journal recovery completes without re-execution")

        let interrupted = WatchExperimentCommand()
        server.enqueue(interrupted)
        server.snapshotFails = true
        await server.execute(interrupted)
        let restarted = Coordinator()
        restarted.journal = server.journal
        let afterRestart = WatchExperimentCommand(
            operation: .requestStatus, targetID: interrupted.requestID
        )
        let uncertain = restarted.requestStatus(afterRestart)
        precondition(uncertain.phase == .unknown && uncertain.error == .resultUnknown)
        precondition(restarted.performed == 0)
        print("PASS: restart keeps unknown without proof and never re-executes")
    }

    @MainActor private static func checkTokens(_ server: Coordinator) async {
        let prepare = WatchExperimentCommand(operation: .prepareStart)
        server.enqueue(prepare)
        let token = UUID()
        server.nextToken = token
        server.tokens[token] = (server.experimentID, .now.advanced(by: .seconds(-1)))
        await server.execute(prepare)
        server.snapshotFails = false
        let expiredQuery = WatchExperimentCommand(
            operation: .requestStatus, targetID: prepare.requestID
        )
        let expired = server.requestStatus(expiredQuery)
        precondition(expired.phase == .failed && expired.error == .requestExpired)
        precondition(server.tokens[token] == nil)
        print("PASS: expired prepare token never becomes completed")

        let live = WatchExperimentCommand(operation: .prepareStart)
        server.enqueue(live)
        let validToken = UUID()
        server.nextToken = validToken
        server.tokens[validToken] = (server.experimentID, .now.advanced(by: .seconds(30)))
        server.snapshotFails = true
        await server.execute(live)
        server.snapshotFails = false
        let liveQuery = WatchExperimentCommand(operation: .requestStatus, targetID: live.requestID)
        let liveResult = server.requestStatus(liveQuery)
        precondition(liveResult.phase == .completed && liveResult.startToken == validToken)
        print("PASS: valid prepare token survives recovery")
    }

    @MainActor private static func checkUnknownMergeRetainsEvidence() async {
        let server = Coordinator()
        let command = WatchExperimentCommand()
        let record = WatchRecordSnapshot(id: UUID())
        server.enqueue(command)
        server.recordResults[command.requestID] = record
        server.snapshotFails = true
        await server.execute(command)
        precondition(server.requests[command.requestID]?.response.phase == .unknown)

        server.snapshotFails = false
        server.forceUnknownMerge = true
        let query = WatchExperimentCommand(operation: .requestStatus, targetID: command.requestID)
        let uncertain = server.requestStatus(query)
        precondition(uncertain.phase == .unknown
                     && uncertain.queriedRequestID == command.requestID)
        precondition(server.completedExecutions[command.requestID] != nil)
        precondition(server.recordResults[command.requestID] == record && server.performed == 1)

        server.forceUnknownMerge = false
        let resolved = server.requestStatus(query)
        precondition(resolved.phase == .completed && resolved.record == record)
        precondition(server.completedExecutions[command.requestID] == nil)
        precondition(server.recordResults[command.requestID] == nil && server.performed == 1)
        print("PASS: unknown media merge retains evidence until resolution")
    }

    @MainActor private static func checkNonterminalMergeRetainsEvidence() async {
        for phase in [WatchExperimentResponse.Phase.received, .processing] {
            let server = Coordinator()
            let command = WatchExperimentCommand()
            let record = WatchRecordSnapshot(id: UUID())
            server.enqueue(command)
            server.recordResults[command.requestID] = record
            server.forceMergedPhase = phase
            await server.execute(command)
            precondition(server.requests[command.requestID]?.response.phase == phase)
            precondition(server.completedExecutions[command.requestID] != nil)
            precondition(server.recordResults[command.requestID] == record)
            let query = WatchExperimentCommand(
                operation: .requestStatus, targetID: command.requestID
            )
            precondition(server.requestStatus(query).phase == phase)
            precondition(server.completedExecutions[command.requestID] != nil)
            server.forceMergedPhase = nil
            let resolved = server.requestStatus(query)
            precondition(resolved.phase == .completed && resolved.record == record)
            precondition(server.completedExecutions[command.requestID] == nil)
            precondition(server.recordResults[command.requestID] == nil && server.performed == 1)
        }
        print("PASS: received and processing retain evidence until terminal result")
    }

    @MainActor private static func checkPartialEffectRemainsUnknown() async {
        let server = Coordinator()
        let command = WatchExperimentCommand()
        server.enqueue(command)
        server.performThrowsAfterEffect = true
        await server.execute(command)
        let query = WatchExperimentCommand(operation: .requestStatus, targetID: command.requestID)
        let result = server.requestStatus(query)
        precondition(server.performed == 1 && result.phase == .unknown)
        precondition(result.error == .resultUnknown)
        precondition(server.completedExecutions[command.requestID] == nil)
        print("PASS: partial effect followed by error remains unknown")
    }

    @MainActor private static func checkOppositeRecordOutcome() {
        let server = Coordinator()
        let saved = WatchRecordSnapshot(id: UUID())
        let cancelled = WatchRecordSnapshot(id: UUID(), phase: .cancelled)
        let cases: [(WatchExperimentCommand.Operation,
                     (WatchRecordSnapshot, WatchExperimentResponse.Phase))] = [
            (.cancelRecord, (saved, .unknown)),
            (.confirmRecord, (cancelled, .unknown)),
            (.cancelRecord, (cancelled, .completed)),
            (.confirmRecord, (saved, .completed)),
            (.other, (saved, .unknown))
        ]
        for (operation, (record, expected)) in cases {
            let command = WatchExperimentCommand(operation: operation)
            server.forcedUnknownRecord = record
            let response = WatchExperimentResponse(requestID: command.requestID, phase: .unknown)
            let result = server.conservativeMediaResult(command, response: response)
            precondition(result.phase == expected && result.record == record)
            if expected == .unknown { precondition(result.error == .resultUnknown) }
        }
        let rejected = WatchExperimentCommand(operation: .cancelRecord)
        server.forcedUnknownRecord = saved
        let failure = WatchExperimentResponse(
            requestID: rejected.requestID, phase: .failed, error: .phoneBusy
        )
        let rejectedResult = server.conservativeMediaResult(rejected, response: failure)
        precondition(rejectedResult.phase == .failed && rejectedResult.error == .phoneBusy)
        print("PASS: opposite media outcomes do not falsely complete uncertain commands")
    }
}
