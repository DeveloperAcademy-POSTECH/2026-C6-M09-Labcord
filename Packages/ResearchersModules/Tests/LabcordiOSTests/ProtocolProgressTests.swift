import Foundation
@testable import LabcordiOS
import XCTest

@MainActor
final class ProtocolProgressTests: XCTestCase {
    func testReadingProgressDrainsInCallbackOrderBeforeReturning() async throws {
        let first = UUID()
        let second = UUID()
        let expected = [
            ReadingUpdate(inputID: first, phase: .identifying),
            ReadingUpdate(inputID: first, phase: .extracting),
            ReadingUpdate(inputID: first, phase: .completed),
            ReadingUpdate(inputID: second, phase: .identifying),
            ReadingUpdate(inputID: second, phase: .failed)
        ]
        let recorder = ProgressRecorder<ReadingUpdate>()
        let client = ProtocolAnalysisClient { _, progress in
            for update in expected { progress?(update.inputID, update.phase) }
            return []
        }

        let results = try await client.parseReportingProgress([]) { inputID, phase in
            await Task.yield()
            await recorder.append(ReadingUpdate(inputID: inputID, phase: phase))
        }
        let received = await recorder.snapshot()
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(received, expected)
    }

    func testReadingProgressDrainsBeforeRethrowingFailure() async throws {
        let identifier = UUID()
        let expected = [
            ReadingUpdate(inputID: identifier, phase: .extracting),
            ReadingUpdate(inputID: identifier, phase: .failed)
        ]
        let recorder = ProgressRecorder<ReadingUpdate>()
        let client = ProtocolAnalysisClient { _, progress in
            for update in expected { progress?(update.inputID, update.phase) }
            throw ProgressTestError.parsingFailed
        }

        do {
            _ = try await client.parseReportingProgress([]) { inputID, phase in
                await Task.yield()
                await recorder.append(ReadingUpdate(inputID: inputID, phase: phase))
            }
            XCTFail("Expected the parser failure to be rethrown")
        } catch {
            XCTAssertEqual(error as? ProgressTestError, .parsingFailed)
        }
        let received = await recorder.snapshot()
        XCTAssertEqual(received, expected)
    }

    func testLegacyTermClientKeepsProgressOptionalAndOutputUnchanged() async throws {
        let source = "sodium chloride"
        let expected = ProtocolExtractedTerms(materials: [source])
        let recorder = ProgressRecorder<ProtocolTermProgress>()
        let client = ProtocolTermClient { text in
            ProtocolExtractedTerms(materials: [text])
        }

        let plain = try await client.extract(source)
        let reporting = try await client.extractWithProgress(source) { event in
            await recorder.append(event)
        }
        let received = await recorder.snapshot()
        XCTAssertEqual(plain, expected)
        XCTAssertEqual(reporting, plain)
        XCTAssertTrue(received.isEmpty)
    }

    func testProgressTermClientKeepsExtractAndProgressOutputEquivalent() async throws {
        let source = "phosphate buffer"
        let recorder = ProgressRecorder<ProtocolTermProgress>()
        let client = ProtocolTermClient { text, progress in
            await progress?(.organizingTerms)
            return ProtocolExtractedTerms(materials: [text])
        }

        let plain = try await client.extract(source)
        let reporting = try await client.extractWithProgress(source) { event in
            await recorder.append(event)
        }
        let received = await recorder.snapshot()
        XCTAssertEqual(plain.materials, [source])
        XCTAssertEqual(reporting, plain)
        XCTAssertEqual(received, [.organizingTerms])
    }

    func testR117EmitsObservedCandidateAndRankingStagesInOrder() async throws {
        let recorder = ProgressRecorder<ProtocolTermProgress>()
        let source = "Add sodium chloride to phosphate buffer and centrifuge for 5 min."
        let result = try await R117TermExtractor().extract(from: source) { event in
            await recorder.append(event)
        }
        let received = await recorder.snapshot()
        XCTAssertFalse(result.isEmpty)
        let candidates = try XCTUnwrap(received.firstIndex(of: .extractingCandidates))
        let preparation = try XCTUnwrap(received.firstIndex(of: .preparingRanking))
        let ranking = try XCTUnwrap(received.firstIndex { event in
            if case .rankingCandidates = event { return true }
            return false
        })
        XCTAssertLessThan(candidates, preparation)
        XCTAssertLessThan(preparation, ranking)
        if let extraction = received.firstIndex(of: .preparingExtraction) {
            XCTAssertLessThan(extraction, candidates)
        }
        guard case let .rankingCandidates(count) = received[ranking] else {
            return XCTFail("Missing the observed candidate count")
        }
        XCTAssertGreaterThan(count, 0)
        XCTAssertGreaterThanOrEqual(count, result.count)
        let rankingProgress = received.enumerated().compactMap { index, event in
            if case let .rankingProgress(completed, total) = event {
                return (index, completed, total)
            }
            return nil
        }
        let last = try XCTUnwrap(rankingProgress.last)
        XCTAssertGreaterThan(last.0, ranking)
        XCTAssertEqual(last.1, count)
        XCTAssertEqual(last.2, count)
    }

    func testEmptyClassificationEmitsOnlyOrganizingStage() async throws {
        let recorder = ProgressRecorder<ProtocolTermProgress>()
        let result = try await ProtocolTermClassifier.classify([], context: "") { event in
            await recorder.append(event)
        }
        let received = await recorder.snapshot()
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(received, [.organizingTerms])
    }
}

private struct ReadingUpdate: Equatable, Sendable {
    let inputID: UUID
    let phase: ProtocolReadingPhase
}

private enum ProgressTestError: Error, Equatable {
    case parsingFailed
}

private actor ProgressRecorder<Event: Sendable> {
    private var events: [Event] = []

    func append(_ event: Event) { events.append(event) }
    func snapshot() -> [Event] { events }
}
