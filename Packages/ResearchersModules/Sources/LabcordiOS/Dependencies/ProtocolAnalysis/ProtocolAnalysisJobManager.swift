import Foundation
import OmniParser

public actor ProtocolAnalysisJobManager {
    public static let shared = ProtocolAnalysisJobManager()
    private let store: ProtocolAnalysisJobStore
    private let parser: ProtocolAnalysisClient
    private let termClient: ProtocolTermClient
    private let usesSystemScheduler: Bool
    private var record: ProtocolAnalysisJobRecord?
    private var phase: ProtocolAnalysisJobPhase = .queued
    private var backgroundAvailable = false
    private var execution: Task<Void, Never>?
    private var draining: (id: UUID, task: Task<Void, Never>)?
    private var runID: UUID?
    private var submissionID: UUID?
    private var listeners: [UUID: AsyncStream<ProtocolAnalysisJobSnapshot>.Continuation] = [:]

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

    public func updates() -> AsyncStream<ProtocolAnalysisJobSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ProtocolAnalysisJobSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        listeners[id] = continuation
        if let value = try? snapshot() { continuation.yield(value) }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeListener(id) }
        }
        return stream
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
        guard execution == nil, record?.status != .queued, record?.status != .running else {
            throw CocoaError(.userCancelled)
        }
        try await drainStoppedExecution()
        guard execution == nil, record?.status != .queued, record?.status != .running else {
            throw CocoaError(.userCancelled)
        }
        let previousID = record?.id
        record = try store.prepare(id: id, inputs: inputs, now: Date())
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

    public func enteredBackground() async {
        guard !backgroundAvailable, let id = record?.id,
              record?.status == .running || record?.status == .queued else { return }
        await pause(id: id, message: "앱을 열면 분석을 이어서 진행할 수 있어요.")
    }
}

private extension ProtocolAnalysisJobManager {
    private func schedule(_ id: UUID) async {
        let submission = UUID()
        submissionID = submission
        #if targetEnvironment(simulator)
        let shouldSchedule = false
        #else
        let shouldSchedule = usesSystemScheduler
        #endif
        if shouldSchedule {
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
            for input in inputs {
                try await process(input, id: id, attempt: attempt)
                publish()
                await updateSystemProgress(id: id)
            }
            try check(id: id, attempt: attempt)
            if let value = record { record = try store.complete(value) }
            execution = nil
            runID = nil
            publish()
            await ProtocolAnalysisBackgroundScheduler.shared.finish(id: id, success: true)
        } catch {
            guard runID == attempt else { return }
            let message = error is CancellationError
                ? "분석이 중단됐어요. 이어서 진행해 주세요."
                : "완료한 내용은 보관했어요. 분석을 이어서 진행해 주세요."
            await pause(id: id, message: message)
        }
    }

    private func process(
        _ input: ProtocolAnalysisJobInput, id: UUID, attempt: UUID
    ) async throws {
        try check(id: id, attempt: attempt)
        let key = input.id.uuidString
        if record?.documents[key] == nil {
            let items = try await parser.parseReportingProgress([
                ProtocolAnalysisInput(id: input.id, url: input.url)
            ]) { inputID, value in
                await self.progress(.reading(inputID, value), id: id, attempt: attempt)
            }
            try check(id: id, attempt: attempt)
            guard let item = items.first, case let .success(document) = item.outcome else {
                throw CocoaError(.fileReadCorruptFile)
            }
            record?.documents[key] = ProtocolAnalysisSavedDocument(document)
            try persist()
        }
        guard let saved = record?.documents[key] else {
            throw CocoaError(.coderReadCorrupt)
        }
        let document = try saved.restored()
        if record?.selected[key] == nil {
            let terms = try await termClient.selectDocumentTerms(document) { value in
                await self.progress(.terms(input.id, value), id: id, attempt: attempt)
            }
            try check(id: id, attempt: attempt)
            record?.selected[key] = terms
            try persist()
        }
        if record?.finished.contains(key) != true {
            let selected = record?.selected[key] ?? []
            let terms = try await classify(
                selected, document: document, input: input.id, id: id, attempt: attempt
            )
            try check(id: id, attempt: attempt)
            record?.classified[key] = ProtocolAnalysisSavedTerms(terms)
            record?.finished.insert(key)
            try persist()
        }
    }

    private func classify(
        _ selected: [String], document: DocumentParseResult, input: UUID,
        id: UUID, attempt: UUID
    ) async throws -> ProtocolExtractedTerms {
        let key = input.uuidString
        let report: ProtocolTermClient.Progress = { value in
            await self.progress(.terms(input, value), id: id, attempt: attempt)
        }
        if let policy = record?.reviewPolicyVersion, let review = termClient.reviewDocumentTerms {
            guard policy == ProtocolTermReviewCheckpoint.currentPolicyVersion else {
                throw ProtocolTermClassifier.ClassificationError.invalidCheckpoint
            }
            return try await review(selected, document, record?.reviews?[key], report) { partial in
                try await self.saveReview(partial, key: key, id: id, attempt: attempt)
            }
        } else {
            let seed = record?.classified[key]?.restored
            return try await termClient.classifyDocumentTerms(
                selected, document.fullText, seed, report
            ) { partial in
                try await self.saveClassification(partial, key: key, id: id, attempt: attempt)
            }
        }
    }

    private func saveReview(
        _ review: ProtocolTermReviewCheckpoint, key: String, id: UUID, attempt: UUID
    ) throws {
        try check(id: id, attempt: attempt)
        guard let selected = record?.selected[key],
              let document = record?.documents[key] else {
            throw ProtocolTermClassifier.ClassificationError.invalidCheckpoint
        }
        try review.validate(terms: selected, source: document.restored().fullText)
        if record?.reviews == nil { record?.reviews = [:] }
        record?.reviews?[key] = review
        try persist()
    }

    private func saveClassification(
        _ terms: ProtocolExtractedTerms, key: String, id: UUID, attempt: UUID
    ) throws {
        try check(id: id, attempt: attempt)
        record?.classified[key] = ProtocolAnalysisSavedTerms(terms)
        try persist()
    }

    private func check(id: UUID, attempt: UUID) throws {
        try Task.checkCancellation()
        guard record?.id == id, record?.status == .running, runID == attempt else {
            throw CancellationError()
        }
    }

    private func progress(_ value: ProtocolAnalysisJobPhase, id: UUID, attempt: UUID) async {
        guard record?.id == id, runID == attempt, record?.status == .running else { return }
        phase = value
        publish()
        await updateSystemProgress(id: id)
    }

    private func updateSystemProgress(id: UUID) async {
        guard let record, record.id == id else { return }
        let progress = ProtocolAnalysisProgress.values(
            record: record, phase: phase
        )
        await ProtocolAnalysisBackgroundScheduler.shared.update(
            id: id, completed: min(progress.total, progress.completed),
            total: progress.total, subtitle: progress.subtitle
        )
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

    private func snapshot() throws -> ProtocolAnalysisJobSnapshot? {
        guard let record else { return nil }
        return try record.snapshot(
            inputs: store.inputs(record), phase: phase, backgroundAvailable: backgroundAvailable
        )
    }

    private func persist() throws {
        guard var value = record else { return }
        value.updatedAt = Date()
        try store.save(value)
        record = value
    }

    private func publish() {
        guard let value = try? snapshot() else { return }
        for listener in listeners.values { listener.yield(value) }
    }
    private func removeListener(_ id: UUID) { listeners[id] = nil }
}
