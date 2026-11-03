import Foundation
@testable import LabcordiOS
import XCTest

final class R117Tests: XCTestCase {
    func testOverlapPenaltyPreservesCanonicalTieOrder() throws {
        let source = "abcdefghij klmn"
        let candidates = [
            candidate("abcdefghij", range: 0..<10, id: "0"),
            candidate("abcdefghi", range: 0..<9, id: "1"),
            candidate("klmn", range: 11..<15, id: "2")
        ]
        let result = try R117Selector.select(
            from: candidates, source: source, scores: [1, 0.95, 0.8]
        )
        XCTAssertEqual(result, [0, 2, 1])
    }

    func testAliasSupportPromotesExplicitLongForm() throws {
        let source = "phosphate buffered saline (PBS)"
        let candidates = [
            candidate("phosphate buffered saline", range: 0..<25, id: "0"),
            candidate("PBS", range: 27..<30, id: "1")
        ]
        let result = try R117Selector.select(
            from: candidates, source: source, scores: [0.1, 0.9]
        )
        XCTAssertEqual(result, [0, 1])
    }

    func testSourceSurfaceMismatchIsRejected() throws {
        let invalid = candidate("wrong", range: 0..<3, id: "0")
        XCTAssertThrowsError(try R117Selector.select(
            from: [invalid], source: "abc", scores: [1]
        ))
    }

    func testPopulationZscoreAndDegeneratePool() throws {
        let values = try R117ScoringMath.zscore([1, 2, 3])
        XCTAssertEqual(values[0], -1.224744871391589, accuracy: 1e-12)
        XCTAssertEqual(values[1], 0)
        XCTAssertEqual(values[2], 1.224744871391589, accuracy: 1e-12)
        XCTAssertEqual(try R117ScoringMath.zscore([5, 5]), [0, 0])
        XCTAssertThrowsError(try R117ScoringMath.zscore([.nan]))
    }

    func testFrozenHandcraftedFeatureOrder() throws {
        let span = R117CandidateSpan(surface: "sodium chloride", start: 4, end: 19)
        let values = try R117HandcraftedFeatures.nine(
            text: "Add sodium chloride for 5 min.", span: span
        )
        XCTAssertEqual(values.count, 9)
        XCTAssertEqual(values[0], log(15), accuracy: 1e-12)
        XCTAssertEqual(values[1], log(3), accuracy: 1e-12)
        XCTAssertEqual(Array(values.dropFirst(2)), [0, 0, 0, 0, 0, 0, 1])
    }

    func testExplicitTimerUnitsDoNotMatchVolumeOrMilliseconds() {
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "5m 30s"), [330])
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "5분 30초"), [330])
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "5ml 3ms"), [])
    }

    func testFullModelPipelineProducesOriginalSurfaces() async throws {
        let text = "Add sodium chloride to the phosphate buffer and centrifuge for 5 min."
        let result = try await R117TermExtractor.shared.extract(from: text)
        XCTAssertFalse(result.isEmpty)
        XCTAssertLessThanOrEqual(result.count, 50)
        for term in result {
            XCTAssertTrue(text.contains(term), "Non-source output: \(term)")
        }
    }

    private func candidate(
        _ text: String, range: Range<Int>, id: String
    ) -> R117SelectionCandidate {
        R117SelectionCandidate(
            id: id, text: text, start: range.lowerBound, end: range.upperBound,
            frozenScore: 0, mentions: [range]
        )
    }
}
