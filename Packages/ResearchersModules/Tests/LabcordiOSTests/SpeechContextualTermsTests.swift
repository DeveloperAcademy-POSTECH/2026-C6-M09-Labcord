import Foundation
@testable import LabcordiOS
import LabcordShared
import XCTest

final class SpeechContextualTermsTests: XCTestCase {
    func testSplitsAliasesAndMethodsWithoutSplittingEnglishPhrases() {
        XCTAssertEqual(
            SpeechContextualTerms.prepare([
                "깔때기(Funnel)", "온도계(전자식)", "가열교반기（Hot plate）", "Funnel"
            ]),
            ["깔때기", "Funnel", "온도계", "전자식", "가열교반기", "Hot plate"]
        )
    }

    func testPreservesConcentrationsChemicalStructureAndAmbiguousAlternatives() {
        let terms = [
            "Standard potassium chloride (0.0100 M)", "Fe(OH)3", "Ca(OH)2",
            "conductivity meter (Wheatstone bridge-type or equivalent)",
            "기압계(기계식_액주형)", "장치(제외)", "장치(선택)", "시약(불완전", "시약(A(B))",
            "영산(HC)", "일산화탄소(CO)", "poly(ethylene glycol)"
        ]
        XCTAssertEqual(SpeechContextualTerms.prepare(terms), terms)
    }

    func testRemovesCalculationDirectiveOnlyFromShortNounPhrases() {
        XCTAssertEqual(
            SpeechContextualTerms.prepare([
                "Compute cell constant", "Calculate temperature coefficient", "cell constant",
                "Determine whether sample is stable", "Compute constant", "Measure resistance"
            ]),
            ["cell constant", "temperature coefficient", "Determine whether sample is stable",
             "Compute constant", "Measure resistance"]
        )
    }

    func testRemovesNumericAnnotationsAndKeepsCaseSensitiveUnitsDistinct() {
        XCTAssertEqual(
            SpeechContextualTerms.prepare([" 시약(2) ", "mM", "mm", "", " ", "mM"]),
            ["시약", "mM", "mm"]
        )
    }

    @MainActor
    func testStoredProtocolFeedsSplitHintsToRecordingDetail() throws {
        let client = ExperimentClient.liveValue
        let id = UUID()
        let experiment = ExperimentProtocol(
            materials: ["깔때기(Funnel)"], glossaryTerms: ["온도계(전자식)"], units: ["mM", "mm"]
        )
        _ = try client.createWithProtocol(id, .now, "STT hint split QA", experiment)
        defer { try? client.delete(id) }
        let detail = try XCTUnwrap(client.loadDetail(id))
        XCTAssertEqual(
            detail.speechContextualStrings,
            ["깔때기", "Funnel", "온도계", "전자식", "mM", "mm"]
        )
    }
}
