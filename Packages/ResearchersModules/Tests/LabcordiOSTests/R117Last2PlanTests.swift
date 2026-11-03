import Foundation
@testable import LabcordiOS
import XCTest

final class R117Last2PlanTests: XCTestCase {
    private static let tokenizer = Result {
        let directory = try XCTUnwrap(R117TermExtractor.resourceDirectory)
        return try R117Tokenizer(
            url: directory.appendingPathComponent("tokenizer/tokenizer.json")
        )
    }

    func testSharedShortContextKeepsDifferentPoolingPositionsAndBOSOffset() throws {
        let tokenizer = try Self.tokenizer.get()
        let text = "sodium chloride phosphate buffer"
        let spans = [0..<6, 7..<15, 16..<25]
        let plan = try R117Last2Plan(text: text, spans: spans, tokenizer: tokenizer)
        let encoding = try tokenizer.encode(text)
        XCTAssertEqual(plan.groups.count, 1)
        let group = try XCTUnwrap(plan.groups.first)
        XCTAssertEqual(group.ids, [0] + encoding.ids + [2])
        XCTAssertEqual(group.selections.map(\.candidate), [0, 1, 2])
        for (selection, range) in zip(group.selections, spans) {
            let expected = encoding.offsets.indices
                .filter { encoding.offsets[$0].overlaps(range) }.map { $0 + 1 }
            XCTAssertEqual(selection.tokens, expected)
            XCTAssertTrue(selection.tokens.allSatisfy { $0 > 0 && $0 < group.ids.count - 1 })
        }
        XCTAssertNotEqual(group.selections[0].tokens, group.selections[1].tokens)
    }

    func testNormalizationCanShareIDsWithoutSharingSourceOffsets() throws {
        let tokenizer = try Self.tokenizer.get()
        let text = "ＡＢＣ" + String(repeating: " ", count: 400) + "ABC"
        let plan = try R117Last2Plan(
            text: text, spans: [0..<3, 403..<406], tokenizer: tokenizer
        )
        XCTAssertEqual(plan.groups.count, 1)
        let group = try XCTUnwrap(plan.groups.first)
        let expected = try tokenizer.encode("ABC")
        XCTAssertEqual(group.ids, [0] + expected.ids + [2])
        XCTAssertEqual(group.selections.map(\.candidate), [0, 1])
        XCTAssertEqual(group.selections[0].tokens, group.selections[1].tokens)
    }

    func testControlNormalizationKeepsWhitespaceAndUnicodeScalarCoordinates() throws {
        let tokenizer = try Self.tokenizer.get()
        let text = "NaCl\u{0000}buffer\nＡＴＰ\t℃\rDNA"
        let normalized = text.replacingOccurrences(of: "\u{0000}", with: " ")
        let spans = [0..<4, 5..<11, 12..<15, 16..<17, 18..<21]
        let plan = try R117Last2Plan(text: text, spans: spans, tokenizer: tokenizer)
        let encoding = try tokenizer.encode(normalized)
        XCTAssertEqual(plan.groups.count, 1)
        let group = try XCTUnwrap(plan.groups.first)
        XCTAssertEqual(group.ids, [0] + encoding.ids + [2])
        for (selection, range) in zip(group.selections, spans) {
            let expected = encoding.offsets.indices
                .filter { encoding.offsets[$0].overlaps(range) }.map { $0 + 1 }
            XCTAssertEqual(selection.tokens, expected)
        }
    }

    func testGroupsKeepFirstAppearanceAndOriginalCandidateIndices() throws {
        let tokenizer = try Self.tokenizer.get()
        let text = "AAA" + String(repeating: " ", count: 400) + "BBB"
        let plan = try R117Last2Plan(
            text: text, spans: [403..<406, 0..<3, 403..<406], tokenizer: tokenizer
        )
        XCTAssertEqual(plan.groups.count, 2)
        XCTAssertEqual(plan.groups.map { $0.selections.map(\.candidate) }, [[0, 2], [1]])
        XCTAssertNotEqual(plan.groups[0].ids, plan.groups[1].ids)
    }

    func testInvalidRangesAreRejectedBeforeContextSlicing() throws {
        let tokenizer = try Self.tokenizer.get()
        for range in [-1..<1, 0..<4, 1..<1, (Int.max - 1)..<Int.max] {
            XCTAssertThrowsError(try R117Last2Plan(
                text: "ABC", spans: [range], tokenizer: tokenizer
            )) { error in
                guard case R117RuntimeError.invalidCandidate = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
        XCTAssertTrue(try R117Last2Plan(text: "", spans: [], tokenizer: tokenizer).groups.isEmpty)
    }

    func testEmptyTokenCoverageIsNotPromotedToSpecialTokenPooling() throws {
        let tokenizer = try Self.tokenizer.get()
        for text in [" \t\n", "\u{0000}"] {
            XCTAssertThrowsError(try R117Last2Plan(
                text: text, spans: [0..<text.unicodeScalars.count], tokenizer: tokenizer
            )) { error in
                guard case R117RuntimeError.uncoveredSource = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testTwoThousandCandidatesArePlannedWithoutLoadingInferenceModels() throws {
        let tokenizer = try Self.tokenizer.get()
        let spans = (0..<2_000).map { $0.isMultiple(of: 2) ? 0..<6 : 7..<15 }
        let plan = try R117Last2Plan(
            text: "sodium chloride buffer", spans: spans, tokenizer: tokenizer
        )
        XCTAssertEqual(plan.groups.count, 1)
        XCTAssertEqual(plan.groups[0].selections.map(\.candidate), Array(0..<2_000))
        XCTAssertEqual(plan.groups[0].selections[0].tokens, plan.groups[0].selections[2].tokens)
        XCTAssertNotEqual(plan.groups[0].selections[0].tokens, plan.groups[0].selections[1].tokens)
    }
}
