import Foundation
import OmniParser

public actor ProtocolAnalysisJobManager {
    public static let shared = ProtocolAnalysisJobManager()
    private let store: ProtocolAnalysisJobStore
    let parser: ProtocolAnalysisClient
    let termClient: ProtocolTermClient
    private let usesSystemScheduler: Bool
    var record: ProtocolAnalysisJobRecord?
    private var phase: ProtocolAnalysisJobPhase = .queued
    private var backgroundAvailable = false
    private var cacheProgress = 0.0
    private var execution: Task<Void, Never>?
    private var draining: (id: UUID, task: Task<Void, Never>)?
    private var runID: UUID?
    private var submissionID: UUID?
    var listeners: [UUID: AsyncStream<ProtocolAnalysisJobSnapshot>.Continuation] = [:]

    public init(
        directory: URL? = nil,
        parser: ProtocolAnalysisClient = .liveValue,
        terms: ProtocolTermClient = .liveValue,
        usesSystemScheduler: Bool = true
    ) {
        store = ProtocolAnalysisJobStore(directory: directory ?? URL.applicationSupportDirectory
            .appendingPathComponent("ProtocolAnalysisJobs", isDirectory: true))
        self.parser = parser
        termClient = terms
        self.usesSystemScheduler = usesSystemScheduler
    }

    public func restore() throws -> ProtocolAnalysisJobSnapshot? {
        if record == nil {
            record = try store.latest()
            if record?.status == .running || record?.status == .queued {
                record?.status = .paused
                record?.message = "중단된 분석을 이어서 진행할 수 있어요."
                try persist()
            }
        }
        return try snapshot()
    }

    public func start(id: UUID, inputs: [ProtocolAnalysisJobInput]) async throws {
        try await start(id: id, inputs: inputs, cached: [])
    }

    public func startCached(
        id: UUID,
        entries: [(input: ProtocolAnalysisJobInput, result: ProtocolAnalysisCachedResult)],
        seconds: Int
    ) async throws {
        try await start(
            id: id, inputs: entries.map(\.input), cached: entries.map(\.result),
            cacheSeconds: seconds
        )
    }

    private func start(
        id: UUID, inputs: [ProtocolAnalysisJobInput], cached: [ProtocolAnalysisCachedResult],
        cacheSeconds: Int? = nil
    ) async throws {
        guard execution == nil, record?.status != .queued, record?.status != .running else {
            throw CocoaError(.userCancelled)
        }
        try await drainStoppedExecution()
        guard execution == nil, record?.status != .queued, record?.status != .running else {
            throw CocoaError(.userCancelled)
        }
        let previousID = record?.id
        var prepared = try store.prepare(id: id, inputs: inputs, now: Date())
        if !cached.isEmpty {
            prepared.replaysCache = true
            prepared.cacheReplaySeconds = cacheSeconds
            do {
                for (input, result) in zip(inputs, cached) {
                    _ = try prepared.recordOutcome(.cached(result), key: input.id.uuidString)
                }
                try store.save(prepared)
            } catch {
                try? store.remove(id)
                throw error
            }
        }
        record = prepared
        cacheProgress = 0
        if let previousID, previousID != id { try? store.remove(previousID) }
        phase = .queued
        publish()
        await schedule(id)
    }

    public func resume(id: UUID) async throws {
        guard execution == nil, record?.id == id,
              record?.status == .paused || record?.status == .failed else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        try await drainStoppedExecution()
        guard execution == nil, record?.id == id,
              record?.status == .paused || record?.status == .failed else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let previousRecord = record
        let previousPhase = phase
        record?.status = .queued
        record?.message = nil
        phase = .queued
        do {
            try persist()
        } catch {
            record = previousRecord
            phase = previousPhase
            throw error
        }
        publish()
        await schedule(id)
    }

    @discardableResult
    public func cancel(id: UUID) async -> Bool {
        guard record?.id == id else { return false }
        let finish = stopExecution(id: id)
        record?.status = .cancelled
        record?.message = nil
        do {
            try persist()
        } catch {
            record?.status = .failed
            record?.message = "분석 취소 상태를 저장하지 못했어요. 다시 시도해 주세요."
            publish()
            await finish.value
            return false
        }
        let cancelled = record
        publish()
        await finish.value
        if let pending = draining { await pending.task.value }
        do {
            if let cancelled { try store.removeInputs(cancelled) }
            return true
        } catch {
            if record?.id == id {
                record?.status = .failed
                record?.message = "분석 파일을 정리하지 못했어요. 다시 시도해 주세요."
                publish()
            }
            return false
        }
    }

    public func resetDebugData() async throws {
        if let id = record?.id { _ = stopExecution(id: id) }
        record = nil
        phase = .queued
        backgroundAvailable = false
        try await drainStoppedExecution()
        if FileManager.default.fileExists(atPath: store.directory.path) {
            try FileManager.default.removeItem(at: store.directory)
        }
    }

    public func enteredBackground() async {
        guard !backgroundAvailable, let id = record?.id,
              record?.status == .running || record?.status == .queued else { return }
        await pause(id: id, message: "앱을 열면 분석을 이어서 진행할 수 있어요.")
    }
}

extension ProtocolAnalysisJobManager {
    private func schedule(_ id: UUID) async {
        let submission = UUID()
        submissionID = submission
        #if targetEnvironment(simulator)
        let shouldSchedule = false
        #else
        let shouldSchedule = usesSystemScheduler
        #endif
        if shouldSchedule && record?.replaysCache != true {
            do {
                backgroundAvailable = true
                try await ProtocolAnalysisBackgroundScheduler.shared.submit(
                    id: id,
                    launch: { await self.launch(id, submission: submission) },
                    expire: { await self.expired(id: id, submission: submission) }
                )
                return
            } catch {
                guard record?.id == id, submissionID == submission else { return }
                backgroundAvailable = false
                record?.message = "앱을 열어둔 상태에서 분석해 주세요. 중단되면 이어서 할 수 있어요."
            }
        }
        backgroundAvailable = false
        if usesSystemScheduler, !(await ProtocolAnalysisBackgroundScheduler.shared.isForeground) {
            await pause(id: id, message: "앱을 열고 분석을 이어서 진행해 주세요.")
            return
        }
        launch(id, submission: submission)
    }

    private func expired(id: UUID, submission: UUID) async {
        guard submissionID == submission else { return }
        await pause(id: id, message: "분석이 중단됐어요. 이어서 진행해 주세요.")
    }

    private func launch(_ id: UUID, submission: UUID) {
        guard submissionID == submission, record?.id == id,
              record?.status == .queued, execution == nil else { return }
        let attempt = UUID()
        runID = attempt
        record?.status = .running
        record?.runStartedAt = Date()
        cacheProgress = 0
        do {
            try persist()
        } catch {
            record?.status = .failed
            record?.message = "분석 진행 상태를 저장하지 못했어요. 다시 시도해 주세요."
            publish()
            Task {
                await ProtocolAnalysisBackgroundScheduler.shared.finish(id: id, success: false)
            }
            return
        }
        publish()
        execution = Task { await self.execute(id: id, attempt: attempt) }
    }

    private func execute(id: UUID, attempt: UUID) async {
        do {
            guard let current = record else { return }
            let inputs = try store.inputs(current)
            if current.replaysCache == true {
                let seconds = current.cacheReplaySeconds ?? 15
                try await replayCache(id: id, attempt: attempt, seconds: seconds)
            } else {
                for input in inputs {
                    try await process(input, id: id, attempt: attempt)
                    publish()
                    await updateSystemProgress(id: id)
                }
            }
            try check(id: id, attempt: attempt)
            let success = record?.failures?.isEmpty != false
            if success {
                if let value = record { record = try store.complete(value) }
            } else {
                record?.status = .failed
                record?.message = "일부 파일을 읽지 못했어요. 파일을 확인하고 다시 시도해 주세요."
                try persist()
            }
            execution = nil
            runID = nil
            publish()
            await ProtocolAnalysisBackgroundScheduler.shared.finish(id: id, success: success)
        } catch {
            guard runID == attempt else { return }
            if !(error is CancellationError) {
                logAnalysisFailure(error, record: record, phase: phase)
            }
            let message = error is CancellationError
                ? "분석이 중단됐어요. 이어서 진행해 주세요."
                : "완료한 내용은 보관했어요. 분석을 이어서 진행해 주세요."
            await pause(id: id, message: message)
        }
    }

    private func replayCache(id: UUID, attempt: UUID, seconds: Int) async throws {
        let clock = ContinuousClock()
        let started = clock.now
        let totalSeconds = min(max(seconds, 1), 60)
        let tickCount = totalSeconds * 10 - 3
        let samples = ProtocolAnalysisCacheProgress.samples(count: tickCount)
        for (index, progress) in samples.enumerated() {
            try await clock.sleep(until: started + .milliseconds((index + 1) * 100))
            try check(id: id, attempt: attempt)
            cacheProgress = progress
            publish()
        }
        // Keep the completed ring visible before publishing the result screen.
        try await clock.sleep(until: started + .seconds(totalSeconds))
    }

    func check(id: UUID, attempt: UUID) throws {
        try Task.checkCancellation()
        guard record?.id == id, record?.status == .running, runID == attempt else {
            throw CancellationError()
        }
    }

    func progress(_ value: ProtocolAnalysisJobPhase, id: UUID, attempt: UUID) async {
        guard record?.id == id, runID == attempt, record?.status == .running else { return }
        phase = value
        publish()
        await updateSystemProgress(id: id)
    }

    private func updateSystemProgress(id: UUID) async {
        guard let record, record.id == id else { return }
        await ProtocolAnalysisSystemProgress.update(record: record, phase: phase)
    }

    private func pause(id: UUID, message: String) async {
        guard record?.id == id, record?.status != .cancelled,
              record?.status != .completed else { return }
        let finish = stopExecution(id: id)
        record?.status = .paused
        record?.message = message
        try? persist()
        publish()
        await finish.value
    }

    private func stopExecution(id: UUID) -> Task<Void, Never> {
        let previous = execution
        let previousDrain = draining?.task
        previous?.cancel()
        execution = nil
        runID = nil
        submissionID = nil
        let finish = Task {
            await ProtocolAnalysisBackgroundScheduler.shared.finish(id: id, success: false)
        }
        let drain = Task {
            await finish.value
            if let previous { await previous.value }
            if let previousDrain { await previousDrain.value }
        }
        draining = (UUID(), drain)
        return finish
    }

    private func drainStoppedExecution() async throws {
        try Task.checkCancellation()
        while let pending = draining {
            await pending.task.value
            try Task.checkCancellation()
            if draining?.id == pending.id { draining = nil }
        }
    }

    internal func snapshot() throws -> ProtocolAnalysisJobSnapshot? {
        guard let record else { return nil }
        return try record.snapshot(
            inputs: store.inputs(record), phase: phase, backgroundAvailable: backgroundAvailable,
            cacheProgress: cacheProgress
        )
    }

    func persist() throws {
        guard var value = record else { return }
        value.updatedAt = Date()
        try store.save(value)
        record = value
    }

    private func publish() {
        guard let value = try? snapshot() else { return }
        for listener in listeners.values { listener.yield(value) }
    }
}
