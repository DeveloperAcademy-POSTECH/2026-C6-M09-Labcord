import Foundation
@testable import LabcordiOS
import OmniParser
import XCTest

private enum JobTestError: Error { case temporary, timeout }

private actor JobProbe {
    enum Behavior { case success, failFirst, blockFirst }
    let behavior: Behavior
    private(set) var parseCount = 0
    private(set) var selectCount = 0
    private(set) var seeds: [ProtocolExtractedTerms?] = []
    private var activeClassifications = 0
    private var maximumClassifications = 0
    private var gate: CheckedContinuation<Void, Never>?
    private let continuation: AsyncStream<Void>.Continuation
    nonisolated let entered: AsyncStream<Void>

    init(_ behavior: Behavior) {
        self.behavior = behavior
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        entered = stream
        self.continuation = continuation
    }

    func parsed() { parseCount += 1 }
    func selected() { selectCount += 1 }
    func classify(
        seed: ProtocolExtractedTerms?, checkpoint: ProtocolTermClient.Checkpoint
    ) async throws -> ProtocolExtractedTerms {
        activeClassifications += 1
        maximumClassifications = max(maximumClassifications, activeClassifications)
        defer { activeClassifications -= 1 }
        seeds.append(seed)
        if behavior == .failFirst && seeds.count == 1 {
            try await checkpoint(.init(materials: ["Aspirin"]))
            throw JobTestError.temporary
        }
        if behavior == .blockFirst && seeds.count == 1 {
            await withCheckedContinuation { gate in
                self.gate = gate
                continuation.yield(())
            }
        }
        return .init(materials: ["Aspirin"], glossaryTerms: ["reaction"])
    }
    func release() { gate?.resume(); gate = nil }
    func counts() -> Counts {
        Counts(
            parse: parseCount, select: selectCount, seeds: seeds,
            maximumClassifications: maximumClassifications
        )
    }

    struct Counts {
        let parse: Int
        let select: Int
        let seeds: [ProtocolExtractedTerms?]
        let maximumClassifications: Int
    }
}

final class ProtocolAnalysisJobManagerTests: XCTestCase {
    private struct Fixture {
        let directory: URL
        let input: ProtocolAnalysisJobInput
        let manager: ProtocolAnalysisJobManager
        let probe: JobProbe
    }

    private func setup(_ behavior: JobProbe.Behavior) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("job-manager-test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.txt")
        try Data("Aspirin reaction".utf8).write(to: source)
        let input = ProtocolAnalysisJobInput(
            id: UUID(), url: source, name: "source.txt", isPhoto: false
        )
        let probe = JobProbe(behavior)
        let document = DocumentParseResult(format: .txt, blocks: [
            .init(kind: .paragraph, text: "Aspirin reaction", readingOrder: 0)
        ], warnings: [])
        let parser = ProtocolAnalysisClient { inputs, progress in
            await probe.parsed()
            if let input = inputs.first { progress?(input.id, .extracting) }
            return inputs.map { .init(id: $0.id, outcome: .success(document)) }
        }
        var terms = ProtocolTermClient { _ in ProtocolExtractedTerms() }
        terms.selectDocumentTerms = { _, _ in
            await probe.selected()
            return ["Aspirin", "reaction"]
        }
        terms.classifyDocumentTerms = { _, _, seed, _, checkpoint in
            try await probe.classify(seed: seed, checkpoint: checkpoint)
        }
        let manager = ProtocolAnalysisJobManager(
            directory: directory.appendingPathComponent("jobs"), parser: parser, terms: terms,
            usesSystemScheduler: false
        )
        return Fixture(directory: directory, input: input, manager: manager, probe: probe)
    }

    private func waitFor(
        _ status: ProtocolAnalysisJobStatus, in stream: AsyncStream<ProtocolAnalysisJobSnapshot>,
        timeout: Duration = .seconds(8)
    ) async throws -> ProtocolAnalysisJobSnapshot {
        try await withThrowingTaskGroup(of: ProtocolAnalysisJobSnapshot.self) { group in
            group.addTask {
                for await value in stream where value.status == status { return value }
                throw JobTestError.timeout
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw JobTestError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private func waitForGate(_ stream: AsyncStream<Void>) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in stream { return }
                throw JobTestError.timeout
            }
            group.addTask {
                try await Task.sleep(for: .seconds(8))
                throw JobTestError.timeout
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }

    func testCompletedPersistsDocumentSelectionAndTerms() async throws {
        let fixture = try setup(.success)
        let directory = fixture.directory
        let input = fixture.input
        let manager = fixture.manager
        let probe = fixture.probe
        defer { try? FileManager.default.removeItem(at: directory) }
        let stream = await manager.updates()
        let id = UUID()
        try await manager.start(id: id, inputs: [input])
        let result = try await waitFor(.completed, in: stream)
        XCTAssertEqual(result.results.first?.extractedText, "Aspirin reaction")
        XCTAssertEqual(result.terms[input.id]?.materials, ["Aspirin"])
        let restored = try await manager.restore()
        XCTAssertEqual(restored?.status, .completed)
        let store = ProtocolAnalysisJobStore(directory: directory.appendingPathComponent("jobs"))
        let saved = try XCTUnwrap(store.latest())
        XCTAssertEqual(saved.status, .completed)
        XCTAssertNotNil(saved.documents[input.id.uuidString])
        XCTAssertEqual(saved.selected[input.id.uuidString], ["Aspirin", "reaction"])
        XCTAssertTrue(saved.finished.contains(input.id.uuidString))
        let counts = await probe.counts()
        XCTAssertEqual(counts.parse, 1)
        XCTAssertEqual(counts.select, 1)
        XCTAssertEqual(counts.seeds.count, 1)
        XCTAssertNil(counts.seeds[0])
    }

    func testCheckpointResumesWithoutParsingOrSelectingAgain() async throws {
        let fixture = try setup(.failFirst)
        let directory = fixture.directory
        let input = fixture.input
        let manager = fixture.manager
        let probe = fixture.probe
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let stream = await manager.updates()
        try await manager.start(id: id, inputs: [input])
        _ = try await waitFor(.paused, in: stream)
        let restoredManager = setupForRestore(directory: directory, probe: probe)
        let restoredSnapshot = try await restoredManager.restore()
        XCTAssertEqual(restoredSnapshot?.status, .paused)
        let resumed = await restoredManager.updates()
        try await restoredManager.resume(id: id)
        let result = try await waitFor(.completed, in: resumed)
        XCTAssertEqual(result.terms[input.id]?.glossaryTerms, ["reaction"])
        let counts = await probe.counts()
        XCTAssertEqual(counts.parse, 1)
        XCTAssertEqual(counts.select, 1)
        XCTAssertEqual(counts.seeds.count, 2)
        XCTAssertEqual(counts.seeds[1]?.materials, ["Aspirin"])
    }

    private func setupForRestore(
        directory: URL, probe: JobProbe
    ) -> ProtocolAnalysisJobManager {
        let parser = ProtocolAnalysisClient { _, _ in
            await probe.parsed()
            return []
        }
        var terms = ProtocolTermClient { _ in ProtocolExtractedTerms() }
        terms.selectDocumentTerms = { _, _ in await probe.selected(); return [] }
        terms.classifyDocumentTerms = { _, _, seed, _, checkpoint in
            try await probe.classify(seed: seed, checkpoint: checkpoint)
        }
        return ProtocolAnalysisJobManager(
            directory: directory.appendingPathComponent("jobs"), parser: parser, terms: terms,
            usesSystemScheduler: false
        )
    }

    func testCancelDiscardsLateClassification() async throws {
        let fixture = try setup(.blockFirst)
        let directory = fixture.directory
        let input = fixture.input
        let manager = fixture.manager
        let probe = fixture.probe
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        try await manager.start(id: id, inputs: [input])
        try await waitForGate(probe.entered)
        await manager.cancel(id: id)
        await probe.release()
        let stream = await manager.updates()
        let result = try await waitFor(.cancelled, in: stream)
        XCTAssertTrue(result.terms.isEmpty)
        do {
            _ = try await waitFor(.completed, in: stream, timeout: .milliseconds(250))
            XCTFail("A late result must not complete a cancelled job")
        } catch JobTestError.timeout {
            // No late completion was published after releasing the suspended classifier.
        }
        let restored = try await manager.restore()
        XCTAssertEqual(restored?.status, .cancelled)
    }

    func testBackgroundPausesAndResumesSavedStages() async throws {
        let fixture = try setup(.blockFirst)
        let directory = fixture.directory
        let input = fixture.input
        let manager = fixture.manager
        let probe = fixture.probe
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        try await manager.start(id: id, inputs: [input])
        try await waitForGate(probe.entered)
        await manager.enteredBackground()
        let restored = try await manager.restore()
        XCTAssertEqual(restored?.status, .paused)
        let stream = await manager.updates()
        let resumed = Task { try await manager.resume(id: id) }
        do {
            _ = try await waitFor(.completed, in: stream, timeout: .milliseconds(150))
            XCTFail("A resumed job must wait for the cancelled classifier to finish")
        } catch JobTestError.timeout { }
        let beforeRelease = await probe.counts()
        XCTAssertEqual(beforeRelease.seeds.count, 1)
        await probe.release()
        try await resumed.value
        _ = try await waitFor(.completed, in: await manager.updates())
        let counts = await probe.counts()
        XCTAssertEqual(counts.parse, 1)
        XCTAssertEqual(counts.select, 1)
        XCTAssertEqual(counts.maximumClassifications, 1)
    }
}

extension ProtocolAnalysisJobManagerTests {
    func testCancelDrainsBeforeStartingAnotherJob() async throws {
        let fixture = try setup(.blockFirst)
        let directory = fixture.directory
        let input = fixture.input
        let manager = fixture.manager
        let probe = fixture.probe
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstID = UUID()
        try await manager.start(id: firstID, inputs: [input])
        try await waitForGate(probe.entered)
        await manager.cancel(id: firstID)
        let stream = await manager.updates()
        let nextID = UUID()
        let started = Task { try await manager.start(id: nextID, inputs: [input]) }
        do {
            _ = try await waitFor(.completed, in: stream, timeout: .milliseconds(150))
            XCTFail("A new job must wait for the cancelled classifier to finish")
        } catch JobTestError.timeout { }
        let beforeRelease = await probe.counts()
        XCTAssertEqual(beforeRelease.parse, 1)
        XCTAssertEqual(beforeRelease.seeds.count, 1)
        await probe.release()
        try await started.value
        let result = try await waitFor(.completed, in: await manager.updates())
        XCTAssertEqual(result.id, nextID)
        let counts = await probe.counts()
        XCTAssertEqual(counts.parse, 2)
        XCTAssertEqual(counts.maximumClassifications, 1)
    }

    func testCancelWhileResumeDrainsDoesNotRestart() async throws {
        let fixture = try setup(.blockFirst)
        let directory = fixture.directory
        let input = fixture.input
        let manager = fixture.manager
        let probe = fixture.probe
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        try await manager.start(id: id, inputs: [input])
        try await waitForGate(probe.entered)
        await manager.enteredBackground()
        let stream = await manager.updates()
        let resumed = Task { try await manager.resume(id: id) }
        do {
            _ = try await waitFor(.completed, in: stream, timeout: .milliseconds(150))
            XCTFail("The suspended classifier has not finished yet")
        } catch JobTestError.timeout { }
        await manager.cancel(id: id)
        await probe.release()
        do {
            try await resumed.value
            XCTFail("A cancelled job must not restart after draining")
        } catch { }
        let restored = try await manager.restore()
        XCTAssertEqual(restored?.status, .cancelled)
        let counts = await probe.counts()
        XCTAssertEqual(counts.seeds.count, 1)
        XCTAssertEqual(counts.maximumClassifications, 1)
    }

    func testDuplicateStartIsRejectedWhileRunning() async throws {
        let fixture = try setup(.blockFirst)
        let directory = fixture.directory
        let input = fixture.input
        let manager = fixture.manager
        let probe = fixture.probe
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        try await manager.start(id: id, inputs: [input])
        try await waitForGate(probe.entered)
        do {
            try await manager.start(id: UUID(), inputs: [input])
            XCTFail("A second running job must be rejected")
        } catch { }
        await manager.cancel(id: id)
        await probe.release()
    }
}
