import Foundation
@testable import LabcordiOS
import OmniParser
import XCTest

final class ProtocolTermSourceCompletionTests: XCTestCase {
    func testMethodAndGeneralDeviceSurfacesArePreserved() {
        XCTAssertEqual(complete(["장비", "원심식"], "장비(원심식)"), ["장비", "원심식"])
        XCTAssertEqual(complete(["원심식"], "장비(원심식)"), ["원심식"])
        XCTAssertEqual(complete(["장비"], "장비(원심식)"), ["장비"])
        XCTAssertEqual(complete(["원심식"], "장비(원심식) 다른장비(원심식)"), ["원심식"])
        XCTAssertEqual(complete(["원심식"], "장비(원심식) 원심식"), ["원심식"])
        XCTAssertEqual(complete(["원심식"], "장비(원심식))"), ["원심식"])
        XCTAssertEqual(complete(["수동식"], "장비(수동식)"), ["수동식"])
        XCTAssertEqual(complete(["참고", "지식"], "참고(지식)"), ["참고", "지식"])
        XCTAssertEqual(complete(["표기", "수식"], "표기(수식)"), ["표기", "수식"])
    }

    func testConcentrationKeepsLiteralSpacingAndUnitCase() {
        let units = ["%", "M", "mM", "µM", "μM", "uM", "mg/mL", "mg/L",
                     "g/L", "g/mL", "mol/L", "mmol/L"]
        for unit in units {
            let source = "시약 (1 \(unit))"
            XCTAssertEqual(complete(["시약"], source), [source])
        }
        XCTAssertEqual(complete(["시약"], "시약(1M) 시약(1mM)"), ["시약"])
    }

    func testAmbiguousAndNonConcentrationParenthesesAreNotCompleted() {
        for source in ["시약(1M) 시약(2M)", "시약(1M) 시약", "시약(2)",
                       "시약(CH3COOH)", "시약(1mM, 2mM)", "시약(1mM", "시약(1mM))"] {
            XCTAssertEqual(complete(["시약"], source), ["시약"], source)
        }
        XCTAssertEqual(complete(["시약"], "시약제(1mM)"), ["시약"])
    }

    func testUnicodeScalarBlockCoordinatesWithEmojiAndCombiningMarks() {
        let prefix = "😀 e\u{301} "
        let term = "시약 (1 mM)"
        let source = prefix + term
        let start = prefix.unicodeScalars.count
        let end = source.unicodeScalars.count
        let result = ProtocolTermSourceCompletion.complete(
            ["시약"], source: source, blocks: [start..<end]
        )
        XCTAssertEqual(result, [term])
        XCTAssertEqual(String(String.UnicodeScalarView(
            Array(source.unicodeScalars)[start..<end]
        )), term)
    }

    func testCountOrderAndExistingCompleteTermsArePreserved() {
        let source = "앞 시약(1mM) 뒤"
        XCTAssertEqual(complete(["앞", "시약", "뒤"], source), ["앞", "시약(1mM)", "뒤"])
        let terms = ["시약", "시약(1mM)"]
        XCTAssertEqual(complete(terms, source), terms)
        XCTAssertEqual(complete(["", "시약(1mM)"], source), ["", "시약(1mM)"])
    }

    func testEveryOccurrenceIsCheckedBeyondStoredMentionLimit() {
        let source = String(repeating: "시약(1mM) ", count: 12)
        XCTAssertEqual(complete(["시약"], source), ["시약(1mM)"])
        XCTAssertEqual(complete(["시약"], source + "시약"), ["시약"])
        XCTAssertEqual(complete(["시약"], source + "시약(2mM)"), ["시약"])
    }

    func testCrossBlockOrInvalidBlockDoesNotComplete() {
        let source = "시약(1mM)"
        let count = source.unicodeScalars.count
        for blocks in [[0..<3, 3..<count], [], [0..<(count + 1)]] {
            XCTAssertEqual(ProtocolTermSourceCompletion.complete(
                ["시약"], source: source, blocks: blocks
            ), ["시약"])
        }
    }

    func testExclusionClauseIsNotTreatedAsPositiveDeviceEvidence() {
        let source = "장비(전도식)\n장비(전도식, 무게식 외의 장비)"
        XCTAssertEqual(complete(["전도식"], source), ["전도식"])
    }

    func testDocumentCleanerKeepsGeneralDeviceAndRepairsExactConcentration() throws {
        let document = DocumentParseResult(format: .pdf, blocks: [
            .init(kind: .paragraph, text: "적설계(레이저식) 염화칼륨 (0.01 M)", readingOrder: 0)
        ], warnings: [])
        XCTAssertEqual(try ProtocolDocumentTermCleaner.clean(
            ["적설계", "레이저식", "염화칼륨"], document: document
        ), ["적설계", "레이저식", "염화칼륨 (0.01 M)"])
    }

    func testCancelledDocumentCompletionDoesNotReturnSelection() async throws {
        let document = DocumentParseResult(format: .pdf, blocks: [
            .init(kind: .paragraph, text: "시약(1mM)", readingOrder: 0)
        ], warnings: [])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ProtocolDocumentTermCleaner.clean(["시약"], document: document)
        }
        do {
            _ = try await task.value
            XCTFail("취소된 문서 정리가 선정 결과를 반환함")
        } catch is CancellationError {
            // 문서 정리 시작과 결과 반환 전의 취소 검사를 유지합니다.
        }
    }

    private func complete(_ terms: [String], _ source: String) -> [String] {
        ProtocolTermSourceCompletion.complete(
            terms, source: source, blocks: [0..<source.unicodeScalars.count]
        )
    }
}
