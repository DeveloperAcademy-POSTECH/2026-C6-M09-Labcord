import Foundation
@testable import LabcordiOS
import UIKit
import XCTest

final class ProtocolLiveParserIntegrationTests: XCTestCase {
    func testLivePDFProgressAndPrecancelledBatch() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makePDF(in: directory)
        let input = ProtocolAnalysisInput(id: UUID(), url: url)
        let second = ProtocolAnalysisInput(id: UUID(), url: url)
        let recorder = LiveParserProbe()
        let results = try await ProtocolAnalysisClient.liveValue.parseReportingProgress(
            [input, second]
        ) { id, phase in
            await recorder.record(id: id, phase: phase)
        }
        XCTAssertEqual(results.first?.id, input.id)
        XCTAssertTrue(results.first?.extractedText?.contains("Aspirin reaction") == true)
        let events = await recorder.events()
        XCTAssertEqual(results.map(\.id), [input.id, second.id])
        for id in [input.id, second.id] {
            let phases = events.filter { $0.id == id }.map(\.phase)
            XCTAssertEqual(phases.first, .identifying)
            XCTAssertEqual(phases.last, .completed)
            XCTAssertTrue(phases.contains(.extracting))
            let ranks = phases.map { phase in
                switch phase {
                case .identifying: 0
                case .extracting: 1
                case .recognizingText: 2
                case .completed: 3
                case .failed, .cancelled: 4
                }
            }
            XCTAssertEqual(ranks, ranks.sorted())
        }

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ProtocolAnalysisClient.liveValue.parse([input], nil)
        }
        do {
            _ = try await cancelled.value
            XCTFail("A cancelled batch must throw")
        } catch is CancellationError {
            // Cancellation is propagated by the live batch client.
        }
    }

    func testLiveBatchCancellationDuringExtractionAndRecovery() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makePDF(in: directory)
        let input = ProtocolAnalysisInput(id: UUID(), url: url)
        let cancellation = LiveCancellationBox()
        let (start, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in start { break }
            return try await ProtocolAnalysisClient.liveValue.parse([input]) { _, phase in
                if phase == .extracting { cancellation.cancel() }
            }
        }
        cancellation.set(task)
        continuation.yield(())
        continuation.finish()
        do {
            _ = try await task.value
            XCTFail("Cancellation during live parsing must throw")
        } catch is CancellationError {
            // The batch propagates cancellation at the extraction boundary.
        }
        let recovered = try await ProtocolAnalysisClient.liveValue.parse([input], nil)
        XCTAssertTrue(recovered.first?.extractedText?.contains("Aspirin reaction") == true)
    }

    func testLiveOCRCancellationAfterRecognitionProgressAndRecovery() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makePDF(in: directory, scanned: true)
        let input = ProtocolAnalysisInput(id: UUID(), url: url)
        let cancellation = LiveCancellationBox()
        let (start, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in start { break }
            return try await ProtocolAnalysisClient.liveValue.parse([input]) { _, phase in
                if phase == .recognizingText { cancellation.cancel() }
            }
        }
        cancellation.set(task)
        continuation.yield(())
        continuation.finish()
        do {
            _ = try await task.value
            XCTFail("Cancellation after recognition progress must throw")
        } catch is CancellationError {
            // This callback follows page recognition; it does not interrupt Vision.
        }
        let recovered = try await ProtocolAnalysisClient.liveValue.parse([input], nil)
        XCTAssertTrue(recovered.first?.extractedText?.contains("Aspirin") == true)
    }

    func testSavedLivePDFParseIsReusedAfterRestore() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makePDF(in: directory)
        let input = ProtocolAnalysisJobInput(
            id: UUID(), url: url, name: "source.pdf", isPhoto: false
        )
        let probe = LiveParserProbe()
        let parser = ProtocolAnalysisClient { inputs, progress in
            await probe.parsed()
            return try await ProtocolAnalysisClient.liveValue.parse(inputs, progress)
        }
        var terms = ProtocolTermClient { _ in ProtocolExtractedTerms() }
        terms.selectDocumentTerms = { document, _ in
            guard document.fullText.contains("Aspirin reaction") else {
                throw LiveParserError.invalidText
            }
            try await probe.select()
            return ["Aspirin"]
        }
        terms.classifyDocumentTerms = { _, _, _, _, _ in .init(materials: ["Aspirin"]) }
        let jobs = directory.appendingPathComponent("jobs")
        let manager = ProtocolAnalysisJobManager(directory: jobs, parser: parser, terms: terms,
                                                 usesSystemScheduler: false)
        let id = UUID()
        let stream = await manager.updates()
        try await manager.start(id: id, inputs: [input])
        let paused = try await waitFor(.paused, stream: stream)
        XCTAssertTrue(paused.results.first?.extractedText?.contains("Aspirin reaction") == true)

        let restored = ProtocolAnalysisJobManager(directory: jobs, parser: parser, terms: terms,
                                                  usesSystemScheduler: false)
        let snapshot = try await restored.restore()
        XCTAssertEqual(snapshot?.status, .paused)
        let updates = await restored.updates()
        try await restored.resume(id: id)
        let completed = try await waitFor(.completed, stream: updates)
        XCTAssertEqual(completed.terms[input.id]?.materials, ["Aspirin"])
        XCTAssertEqual(completed.results, paused.results)
        let count = await probe.parseCount()
        XCTAssertEqual(count, 1)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-parser-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makePDF(in directory: URL, scanned: Bool = false) throws -> URL {
        let url = directory.appendingPathComponent("source.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 300))
        let data = renderer.pdfData { context in
            context.beginPage()
            if scanned {
                let imageRenderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300))
                let image = imageRenderer.image { _ in
                    UIColor.white.setFill()
                    UIRectFill(CGRect(x: 0, y: 0, width: 300, height: 300))
                    "Aspirin reaction".draw(at: CGPoint(x: 20, y: 20), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 24)
                    ])
                }
                image.draw(at: .zero)
            } else {
                "Aspirin reaction".draw(at: CGPoint(x: 20, y: 20), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 18)
                ])
            }
        }
        try data.write(to: url)
        return url
    }

    private func waitFor(
        _ status: ProtocolAnalysisJobStatus, stream: AsyncStream<ProtocolAnalysisJobSnapshot>
    ) async throws -> ProtocolAnalysisJobSnapshot {
        try await withThrowingTaskGroup(of: ProtocolAnalysisJobSnapshot.self) { group in
            group.addTask {
                for await value in stream where value.status == status { return value }
                throw LiveParserError.timeout
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw LiveParserError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

private enum LiveParserError: Error { case temporary, invalidText, timeout }

private actor LiveParserProbe {
    private var updates: [LiveProgress] = []
    private var parses = 0
    private var selections = 0

    func record(id: UUID, phase: ProtocolReadingPhase) {
        updates.append(LiveProgress(id: id, phase: phase))
    }
    func events() -> [LiveProgress] { updates }
    func parsed() { parses += 1 }
    func parseCount() -> Int { parses }
    func select() throws {
        selections += 1
        if selections == 1 { throw LiveParserError.temporary }
    }
}

private final class LiveCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<[ProtocolAnalysisItem], Error>?

    func set(_ task: Task<[ProtocolAnalysisItem], Error>) {
        lock.lock()
        defer { lock.unlock() }
        self.task = task
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        task?.cancel()
    }
}

private struct LiveProgress: Sendable {
    let id: UUID
    let phase: ProtocolReadingPhase
}
