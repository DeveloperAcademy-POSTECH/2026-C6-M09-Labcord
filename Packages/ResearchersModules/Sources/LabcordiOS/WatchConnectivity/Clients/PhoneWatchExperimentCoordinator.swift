import ComposableArchitecture
import Foundation
import LabcordShared
import UIKit

@MainActor
public final class PhoneWatchExperimentCoordinator {
    public static let shared = PhoneWatchExperimentCoordinator()
    public var isBusy = false
    public var visibleExperimentID: UUID?
    public var phoneSceneIsActive = false
    private static let pendingStartKey = "labcord.watch.pendingStartID"
    public internal(set) var pendingStartID: UUID? {
        didSet { persistPendingStart() }
    }

    public enum Event: Sendable {
        case command(WatchExperimentCommand)
        case started(UUID)
    }
    /// #174는 실제 저장까지 기다리고 실패를 throw하는 handler를 등록합니다.
    public var recordHandler: ((WatchExperimentCommand) async throws -> Void)?
    /// 진행 중인 기록의 중지·저장을 기존 자식 Feature로 전달하고 완료를 기다립니다.
    public var prepareSessionClose: ((WatchExperimentCommand) async throws -> Void)?

    let connectivity: WatchConnectivitySession
    let client: ExperimentClient
    var revisionURL = URL.applicationSupportDirectory
        .appendingPathComponent("WatchExperiment/revision.txt")
    var journal: WatchExperimentRequestJournal?
    var requests: [UUID: WatchExperimentRequestJournal.Entry] = [:]
    var tokens: [UUID: (UUID, ContinuousClock.Instant)] = [:]
    var states: [UUID: WatchExperimentState] = [:]
    var revisions: [UUID: UInt64] = [:]
    var phoneSessionFlags: [UUID: Bool] = [:]
    var recordResults: [UUID: WatchRecordSnapshot] = [:]
    var recordSnapshots: [UUID: WatchRecordSnapshot] = [:]
    var completedExecutions: [UUID: WatchCompletedExecution] = [:]
    var executing: UUID?
    var photoCancellationID: UUID?
    var subscriberID: UUID?
    var commandSubscriber: AsyncStream<Event>.Continuation?
    var completions: [UUID: CheckedContinuation<Void, Error>] = [:]
    var refreshTask: Task<Void, Never>?

    public init() {
        @Dependency(\.watchConnectivitySession) var connectivity
        @Dependency(\.experimentClient) var client
        self.connectivity = connectivity
        self.client = client
    }

    public func activate() {
        guard connectivity.experiments.receiveCommand == nil else { return }
        loadJournal()
        connectivity.experiments.receiveCommand = { [weak self] command in
            self?.receive(command) ?? WatchExperimentResponse(
                requestID: command.requestID, phase: .failed, error: .phoneBusy
            )
        }
        connectivity.activate()
    }

    func loadJournal() {
        guard journal == nil else { return }
        let directory = revisionURL.deletingLastPathComponent()
        journal = try? WatchExperimentRequestJournal(
            url: directory.appendingPathComponent("requests.json")
        )
        pendingStartID = UserDefaults.standard.string(forKey: Self.pendingStartKey)
            .flatMap(UUID.init(uuidString:))
    }

    public func events() -> AsyncStream<Event> {
        let id = UUID()
        return AsyncStream { continuation in
            failPendingCommands()
            commandSubscriber?.finish()
            subscriberID = id
            commandSubscriber = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    guard self?.subscriberID == id else { return }
                    self?.commandSubscriber = nil
                    self?.subscriberID = nil
                    self?.failPendingCommands()
                }
            }
        }
    }

    func failPendingCommands() {
        let pending = completions.values
        completions.removeAll()
        for continuation in pending {
            continuation.resume(throwing: WatchExperimentError.resultUnknown)
        }
    }

    public func didOpen(_ id: UUID) {
        if pendingStartID == id { pendingStartID = nil }
    }

    public func finish(_ id: UUID, error: WatchExperimentError? = nil) {
        guard let continuation = completions.removeValue(forKey: id) else { return }
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    public func rejectUndispatchedRecord(_ id: UUID) {
        completions.removeValue(forKey: id)?
            .resume(throwing: WatchDefinitiveRejection(error: .phoneBusy))
    }

    func receive(_ command: WatchExperimentCommand) -> WatchExperimentResponse {
        guard command.version == WatchExperimentCommand.schemaVersion else {
            return failure(command, .unsupportedVersion)
        }
        guard UIApplication.shared.isProtectedDataAvailable else {
            return failure(command, .phoneUnlockRequired)
        }
        loadJournal()
        if let response = existingResponse(command) { return response }
        if let response = query(command) {
            requests[command.requestID] = .init(command: command, response: response)
            return response
        }
        guard journal != nil else { return failure(command, .storageFailed) }
        let response = WatchExperimentResponse(requestID: command.requestID, phase: .received)
        do {
            try journal?.save(command, response: response)
        } catch { return failure(command, .storageFailed) }
        requests[command.requestID] = .init(command: command, response: response)
        Task { await execute(command) }
        return response
    }

    func existingResponse(_ command: WatchExperimentCommand) -> WatchExperimentResponse? {
        guard let entry = requests[command.requestID] ?? journal?.entries[command.requestID]
        else { return nil }
        guard entry.command == command else { return failure(command, .duplicateConflict) }
        if requests[command.requestID] == nil,
           [.received, .processing].contains(entry.response.phase) {
            return unknownOutcome(command)
        }
        return entry.response
    }

    func query(_ command: WatchExperimentCommand) -> WatchExperimentResponse? {
        if command.operation == .requestStatus { return requestStatus(command) }
        if command.operation == .list {
            do {
                let summaries = try client.loadForWatch().compactMap { entry in
                    try client.watchState(entry.id)?.experiment
                }
                if phoneSceneIsActive, UIApplication.shared.applicationState == .active,
                   let id = visibleExperimentID, let value = try? snapshot(id),
                   value.phoneSessionActive == true {
                    publish(value)
                }
                return WatchExperimentResponse(
                    requestID: command.requestID, phase: .completed, experiments: summaries
                )
            } catch { return failure(command, .storageFailed) }
        }
        if command.operation == .snapshot {
            guard let id = command.experimentID else { return failure(command, .invalidPayload) }
            do {
                return WatchExperimentResponse(
                    requestID: command.requestID, phase: .completed, snapshot: try snapshot(id)
                )
            } catch { return failure(command, error as? WatchExperimentError ?? .storageFailed) }
        }
        return nil
    }

    func requestStatus(_ command: WatchExperimentCommand) -> WatchExperimentResponse {
        guard let id = command.targetID else { return failure(command, .invalidPayload) }
        if let original = requests[id]?.command ?? journal?.entries[id]?.command,
           let experimentID = original.experimentID {
            do { try restoreSavedRecords(experimentID) } catch {
                return unknownOutcome(command, queriedRequestID: id)
            }
        }
        if let entry = requests[id], completedExecutions[id] != nil,
           [.unknown, .received, .processing].contains(entry.response.phase) {
            recoverCompletedExecution(entry)
        }
        let entry = requests[id] ?? journal?.entries[id]
        guard let entry else {
            return WatchExperimentResponse(
                requestID: command.requestID, phase: .unknown, error: .resultUnknown,
                queriedRequestID: id
            )
        }
        let response = conservativeMediaResult(entry.command, response: entry.response)
        // 조회 envelope의 ID는 조회 요청의 ID이며 targetID의 결과를 담습니다.
        let interrupted = requests[id] == nil
            && (response.phase == .received || response.phase == .processing)
        return WatchExperimentResponse(
            requestID: command.requestID, phase: interrupted ? .unknown : response.phase,
            experiments: response.experiments, snapshot: response.snapshot,
            error: interrupted ? .resultUnknown : response.error,
            startToken: response.startToken, record: response.record, queriedRequestID: id
        )
    }

    func execute(_ command: WatchExperimentCommand) async {
        let response: WatchExperimentResponse
        var didPerform = false
        do {
            try beginExecution(command)
            defer { finishExecution(command.requestID) }
            requests[command.requestID]?.response = WatchExperimentResponse(
                requestID: command.requestID, phase: .processing
            )
            let current = try validate(command)
            let id = current.experiment.id
            let token = try await perform(command, current: current)
            didPerform = true
            completedExecutions[command.requestID] = WatchCompletedExecution(
                experimentID: id, startToken: token, record: recordResults[command.requestID]
            )
            let updated = try snapshot(id)
            publish(updated)
            response = WatchExperimentResponse(
                requestID: command.requestID, phase: .completed,
                snapshot: updated, startToken: token,
                record: recordResults[command.requestID]
            )
        } catch {
            response = didPerform || error is WatchExecutionUncertain
                || (error as? WatchExperimentError) == .resultUnknown ? unknownOutcome(command)
                : failure(command, error as? WatchExperimentError ?? .storageFailed)
        }
        let result = conservativeMediaResult(command, response: response)
        do {
            try journal?.save(command, response: result)
            requests[command.requestID]?.response = result
            if result.phase == .completed || result.phase == .failed {
                completedExecutions.removeValue(forKey: command.requestID)
                recordResults.removeValue(forKey: command.requestID)
            }
        } catch {
            requests[command.requestID]?.response = unknownOutcome(command)
        }
    }

    func snapshot(_ id: UUID) throws -> WatchExperimentSnapshot {
        guard let state = try client.watchState(id) else {
            throw WatchExperimentError.experimentNotFound
        }
        try restoreSavedRecords(id)
        let active = WatchSnapshotPublicationPolicy.isPhoneSessionActive(
            id: id, visible: visibleExperimentID, sceneActive: phoneSceneIsActive,
            applicationActive: UIApplication.shared.applicationState == .active,
            running: state.experiment.status == .running
        )
        if states[id] != state || phoneSessionFlags[id] != active {
            let next = try nextRevision()
            revisions[id] = next
            states[id] = state
            phoneSessionFlags[id] = active
        }
        return state.snapshot(revision: revisions[id] ?? 0, at: .now, phoneSessionActive: active)
    }

    func failure(_ command: WatchExperimentCommand, _ error: WatchExperimentError)
        -> WatchExperimentResponse {
        WatchExperimentResponse(requestID: command.requestID, phase: .failed, error: error)
    }
}

extension PhoneWatchExperimentCoordinator {
    public func refresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            self.refreshTask = nil
            let ids = WatchSnapshotPublicationPolicy.orderedIDs(
                known: Set(states.keys), visible: visibleExperimentID
            )
            for id in ids {
                if let snapshot = try? snapshot(id) { publish(snapshot) }
            }
        }
    }

    func nextRevision() throws -> UInt64 {
        var previous: UInt64 = 0
        if FileManager.default.fileExists(atPath: revisionURL.path) {
            let data = try Data(contentsOf: revisionURL)
            guard let value = String(data: data, encoding: .utf8).flatMap(UInt64.init) else {
                throw WatchExperimentError.storageFailed
            }
            previous = value
        }
        guard previous < UInt64.max else { throw WatchExperimentError.storageFailed }
        let next = previous + 1
        try FileManager.default.createDirectory(
            at: revisionURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(String(next).utf8).write(
            to: revisionURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        return next
    }

    func publish(_ snapshot: WatchExperimentSnapshot) {
        guard let session = connectivity.session, session.activationState == .activated,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        var context = session.applicationContext
        context[WatchExperimentTransport.snapshotKey] = data
        try? session.updateApplicationContext(context)
    }

}

extension PhoneWatchExperimentCoordinator {
    func conservativeMediaResult(
        _ command: WatchExperimentCommand, response: WatchExperimentResponse
    ) -> WatchExperimentResponse {
        let merged = latestMediaResult(command, response: response)
        if response.phase == .failed {
            return WatchExperimentResponse(
                requestID: merged.requestID, phase: .failed, experiments: merged.experiments,
                snapshot: merged.snapshot, error: response.error, startToken: merged.startToken,
                record: merged.record, queriedRequestID: merged.queriedRequestID
            )
        }
        guard response.phase == .unknown else { return merged }
        if merged.phase == .completed {
            let confirmsSaved = command.operation == .confirmRecord
                && merged.record?.phase == .saved
            let confirmsCancelled = command.operation == .cancelRecord
                && merged.record?.phase == .cancelled
            if confirmsSaved || confirmsCancelled { return merged }
        } else if merged.phase != .failed {
            return merged
        }
        return WatchExperimentResponse(
            requestID: merged.requestID, phase: .unknown, experiments: merged.experiments,
            snapshot: merged.snapshot, error: .resultUnknown, startToken: merged.startToken,
            record: merged.record, queriedRequestID: merged.queriedRequestID
        )
    }
}

private extension PhoneWatchExperimentCoordinator {
    func unknownOutcome(
        _ command: WatchExperimentCommand, queriedRequestID: UUID? = nil
    ) -> WatchExperimentResponse {
        // 실행이 끝난 뒤 조회만 실패한 경우 결과를 단정하거나 재실행하지 않는다.
        WatchExperimentResponse(
            requestID: command.requestID, phase: .unknown, error: .resultUnknown,
            queriedRequestID: queriedRequestID
        )
    }

    func persistPendingStart() {
        if let pendingStartID {
            UserDefaults.standard.set(pendingStartID.uuidString, forKey: Self.pendingStartKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.pendingStartKey)
        }
    }
}
