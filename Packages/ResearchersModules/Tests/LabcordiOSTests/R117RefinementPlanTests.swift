import Foundation
@testable import LabcordiOS
import XCTest

final class R117RefinementPlanTests: XCTestCase {
    func testRawScorePlanKeepsCanonicalIndexOrderForTies() throws {
        let plan = try R117Ranker.RefinementPlan(scores: [5, 8, 8, -1, 7], limit: 3)
        XCTAssertEqual(plan.indices, [1, 2, 4])
        XCTAssertEqual(plan.total, 5)
        XCTAssertEqual(plan.completedBeforeRefinement, 2)
        let all = try R117Ranker.RefinementPlan(scores: [2, 5, 1], limit: Int.max)
        XCTAssertEqual(all.indices, [1, 0, 2])
        XCTAssertEqual(all.completedBeforeRefinement, 0)
    }

    func testInvalidLimitsAndNonfiniteScoresAreRejectedBeforePlanning() {
        for limit in [0, -1, Int.min] {
            XCTAssertThrowsError(try R117Ranker.RefinementPlan(scores: [1, 2], limit: limit))
        }
        for scores in [[Double](), [1, .nan], [.infinity], [-.infinity]] {
            XCTAssertThrowsError(try R117Ranker.RefinementPlan(scores: scores, limit: 1))
        }
    }

    func testShortInputsUseCandidateModeBeforeSharedEncoding() throws {
        let mode = R117Ranker.ContextMode.documentSharedRefined(limit: 100)
        XCTAssertEqual(try mode.forCandidateCount(1), .candidate)
        XCTAssertEqual(try mode.forCandidateCount(100), .candidate)
        XCTAssertEqual(try mode.forCandidateCount(101), mode)
        XCTAssertEqual(try mode.forCandidateCount(2_000), mode)
        XCTAssertEqual(try R117Ranker.ContextMode.candidate.forCandidateCount(1), .candidate)
        XCTAssertEqual(
            try R117Ranker.ContextMode.documentShared.forCandidateCount(1), .documentShared
        )
        XCTAssertThrowsError(try mode.forCandidateCount(0))
        for limit in [0, -1] {
            XCTAssertThrowsError(
                try R117Ranker.ContextMode.documentSharedRefined(limit: limit).forCandidateCount(1)
            )
        }
    }

    func testExactLogitsReplaceOnlyPlannedIndicesInTheirReturnedOrder() throws {
        let plan = try R117Ranker.RefinementPlan(scores: [1, 3, 4, 2], limit: 2)
        let coarse = trace()
        let refined = try plan.replacingLast2(in: coarse, with: [30, 20])
        XCTAssertEqual(refined.components.last2, [1, 20, 30, 4])
        XCTAssertEqual(refined.components.native, coarse.components.native)
        XCTAssertEqual(refined.components.frozen9, coarse.components.frozen9)
        XCTAssertEqual(refined.components.hgb, coarse.components.hgb)
        XCTAssertEqual(refined.components.window, coarse.components.window)
        XCTAssertEqual(refined.components.scope, coarse.components.scope)
        XCTAssertEqual(refined.components.purpose, coarse.components.purpose)
        XCTAssertEqual(refined.headLogits, coarse.headLogits)
    }

    func testFullPoolCombinationUpdatesUnrefinedScoresThroughNormalization() throws {
        let plan = try R117Ranker.RefinementPlan(scores: [4, 3, 2, 1], limit: 1)
        let coarse = trace()
        let refined = try plan.replacingLast2(in: coarse, with: [10])
        let before = try R117ScoringMath.combine(
            coarse.components, headLogits: coarse.headLogits
        )
        let after = try R117ScoringMath.combine(
            refined.components, headLogits: refined.headLogits
        )
        let expected = trace(last2: [10, 2, 3, 4])
        XCTAssertEqual(
            after, try R117ScoringMath.combine(
                expected.components, headLogits: expected.headLogits
            )
        )
        XCTAssertNotEqual(after[1], before[1])
        XCTAssertNotEqual(after[2], before[2])
        XCTAssertNotEqual(after[3], before[3])
    }

    func testMalformedTraceOrExactLogitsCannotBePatched() throws {
        let plan = try R117Ranker.RefinementPlan(scores: [4, 3, 2, 1], limit: 2)
        for logits in [[Double](), [1], [1, 2, 3], [1, .nan], [1, .infinity]] {
            XCTAssertThrowsError(try plan.replacingLast2(in: trace(), with: logits))
        }
        for invalid in [
            trace(last2: [1, 2, 3]), trace(last2: [1, 2, .nan, 4]),
            trace(headLogits: [1]), trace(headLogits: [1, 2, .infinity, 4]),
            trace(hgb: [1, 2]), trace(hgb: [1, .nan, 3, 4])
        ] {
            XCTAssertThrowsError(try plan.replacingLast2(in: invalid, with: [5, 6]))
        }
    }

    private func trace(
        last2: [Double] = [1, 2, 3, 4], headLogits: [Double] = [0.1, 0.2, 0.3, 0.4],
        hgb: [Double] = [1, 3, 4, 2]
    ) -> R117Ranker.Trace {
        R117Ranker.Trace(
            components: R117ScoringMath.Components(
                native: [0, 0, 0, 0], frozen9: [0, 0, 0, 0], hgb: hgb,
                window: [2, 3, 5, 4], scope: [4, 2, 1, 3], purpose: [1, 0, 2, 5], last2: last2
            ), headLogits: headLogits
        )
    }
}
