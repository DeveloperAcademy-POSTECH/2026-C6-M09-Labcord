import Foundation
@testable import LabcordiOS
import XCTest

final class R117HandcraftedFeaturesTests: XCTestCase {
    func testFrozenGreekChemicalFeatureColumns() throws {
        let document = R117HandcraftedFeatures.Document(text: "\n1. Add β2−NaCl (소금) 5 mL\n")
        let span = R117CandidateSpan(surface: "β2−NaCl", start: 8, end: 15)
        let expectedNine: [Double] = [log(7.0), log(2.0), 1, 1, 0, 0, 0, 1, 1]
        let expectedRemaining: [Double] = [
            1, 0, 1, 1, 0, 0, 1, 0, 0, 0,
            1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1
        ]
        assertFeatures(try document.nine(span: span), equalTo: expectedNine)
        assertFeatures(
            try document.combined32(span: span), equalTo: expectedNine + expectedRemaining
        )
    }

    func testCombinedFeaturesKeep160ScalarContextBoundary() throws {
        let prefix = "materials" + String(repeating: " ", count: 170)
        let source = prefix + "term" + String(repeating: " ", count: 160) + "protocol"
        let start = prefix.unicodeScalars.count
        let span = R117CandidateSpan(surface: "term", start: start, end: start + 4)
        let document = R117HandcraftedFeatures.Document(text: source)
        let nine = try document.nine(span: span)
        let combined = try document.combined32(span: span)
        XCTAssertEqual(nine[6], 1)
        XCTAssertEqual(combined[6], 0)
        XCTAssertEqual(combined[30], 0)
        XCTAssertEqual(combined[31], 0)
    }

    func testSourceOffsetsRemainUnicodeScalarBased() throws {
        let prefix = "🧪e\u{0301}\u{001C}측정 "
        let source = prefix + "µL 시약"
        let start = prefix.unicodeScalars.count
        let span = R117CandidateSpan(surface: "µL", start: start, end: start + 2)
        let document = R117HandcraftedFeatures.Document(text: source)
        let result = try document.combined32(span: span)
        XCTAssertEqual(result[0], log(3), accuracy: 1e-12)
        XCTAssertEqual(result[3], 1)
        XCTAssertEqual(result[6], 1)
        XCTAssertEqual(result[17], 1)
        XCTAssertThrowsError(try document.nine(span: .init(
            surface: "µL", start: start - 1, end: start + 1
        )))
    }

    func testPythonWordBoundaryExcludesCombiningMarks() throws {
        let prefix = "add\u{0301} "
        let source = prefix + "term 5 mL\u{0301}"
        let start = prefix.unicodeScalars.count
        let span = R117CandidateSpan(surface: "term", start: start, end: start + 4)
        let result = try R117HandcraftedFeatures.Document(text: source).combined32(span: span)
        XCTAssertEqual(result[30], 1)
        XCTAssertEqual(result[31], 1)
    }

    func testSuperscriptDigitRetainsDistinctRegexSemantics() throws {
        let span = R117CandidateSpan(surface: "A²", start: 0, end: 2)
        let document = R117HandcraftedFeatures.Document(text: "A²")
        let result = try document.combined32(span: span)
        XCTAssertEqual(result[0], log(3), accuracy: 1e-12)
        XCTAssertEqual(result[2], 1)
        XCTAssertEqual(result[12], 1)
        XCTAssertEqual(result[14], 0)
        XCTAssertThrowsError(try document.combined32(span: .init(
            surface: "A²", start: -1, end: 1
        )))
        XCTAssertThrowsError(try document.combined32(span: .init(
            surface: "A²", start: 0, end: 3
        )))
    }

    private func assertFeatures(_ values: [Double], equalTo expected: [Double]) {
        XCTAssertEqual(values.count, expected.count)
        for (index, pair) in zip(values, expected).enumerated() {
            XCTAssertEqual(pair.0, pair.1, accuracy: 1e-12, "Feature column \(index)")
        }
    }
}
