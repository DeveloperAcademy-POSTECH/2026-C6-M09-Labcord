import ComposableArchitecture
import Foundation
import LabcordShared
import UIKit

@MainActor
public final class PhoneWatchExperimentCoordinator {
    public static let shared = PhoneWatchExperimentCoordinator()
    public var isBusy = false
    public var visibleExperimentID: UUID?
    public internal(set) var pendingStartID: UUID?

    public enum Event: Sendable {
        case command(WatchExperimentCommand)
        case started(UUID)
    }

    public var recordHandler: ((WatchExperimentCommand) async throws -> Void)?

    public var prepareSessionClose: ((WatchExperimentCommand) async throws -> Void)?

    let connectivity: WatchConnectivitySession
    let client: ExperimentClient
    var revisionURL = URL.applicationSupportDirectory
        .appendingPathComponent("WatchExperiment/revision.txt")
    var journal: WatchExperimentRequestJournal?
    var requests: [UUID: WatchExperimentRequestJournal.Entry] = [:]
    private var recentQueries = WatchExperimentQueryCache()
    var tokens: [UUID: (experimentID: UUID, expiresAt: ContinuousClock.Instant)] = [:]
    var states: [UUID: WatchExperimentState] = [:]
    var revisions: [UUID: UInt64] = [:]
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
        pendingStartID = journal?.entries.values
            .compactMap { $0.response.snapshot }
            .max { $0.recordedAt < $1.recordedAt }
            .flatMap { $0.experiment.status == .running ? $0.experiment.id : nil }
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

    public func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            for id in Array(states.keys) {
                if let snapshot = try? snapshot(id) { publish(snapshot) }
            }
        }
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
            recentQueries.store(command, response: response)
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
        if let response = recentQueries.response(for: command) { return response }
        guard let entry = requests[command.requestID] ?? journal?.entries[command.requestID]
        else { return nil }
        guard entry.command == command else { return failure(command, .duplicateConflict) }
        if requests[command.requestID] == nil,
           [.received, .processing].contains(entry.response.phase) {
            return failure(command, .resultUnknown)
        }
        return entry.response
    }

    func query(_ command: WatchExperimentCommand) -> WatchExperimentResponse? {
        if command.operation == .requestStatus { return requestStatus(command) }
        if command.operation == .list {
            do {
                let summaries = try client.load().compactMap { entry in
                    try client.watchState(entry.id)?.experiment
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
        let response = requests[id]?.response ?? journal?.entries[id]?.response
            ?? recentQueries.response(for: id)
        guard let response else {
            return WatchExperimentResponse(
                requestID: command.requestID, phase: .unknown, error: .resultUnknown,
                queriedRequestID: id
            )
        }

        let interrupted = requests[id] == nil && recentQueries.response(for: id) == nil
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
        do {
            try beginExecution(command)
            defer { finishExecution(command.requestID) }
            requests[command.requestID]?.response = WatchExperimentResponse(
                requestID: command.requestID, phase: .processing
            )
            let current = try validate(command)
            let id = current.experiment.id
            let token = try await perform(command, current: current)
            let updated = try snapshot(id)
            publish(updated)
            response = WatchExperimentResponse(
                requestID: command.requestID, phase: .completed,
                snapshot: updated, startToken: token
            )
        } catch {
            response = failure(command, error as? WatchExperimentError ?? .storageFailed)
        }
        do {
            try journal?.save(command, response: response)
            requests[command.requestID]?.response = response
        } catch {
            requests[command.requestID]?.response = failure(command, .resultUnknown)
        }
    }

    func snapshot(_ id: UUID) throws -> WatchExperimentSnapshot {
        guard let state = try client.watchState(id) else {
            throw WatchExperimentError.experimentNotFound
        }
        if states[id] != state {
            let next = try nextRevision()
            revisions[id] = next
            states[id] = state
        }
        return state.snapshot(revision: revisions[id] ?? 0, at: .now)
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
            to: revisionURL, options: [.atomic, .completeFileProtection]
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

    func failure(_ command: WatchExperimentCommand, _ error: WatchExperimentError)
        -> WatchExperimentResponse {
        WatchExperimentResponse(requestID: command.requestID, phase: .failed, error: error)
    }
}
