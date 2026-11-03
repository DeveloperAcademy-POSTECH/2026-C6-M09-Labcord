import Foundation
@testable import LabcordiOS
import OmniParser
import XCTest

final class ProtocolDocumentTermCleanerTests: XCTestCase {
    func testBalancedChemicalNotationAndUnambiguousParenthesesAreRestored() throws {
        let source = "금속제(시스형)온도계 [14C]glucose Fe(OH)3 ＡＴＰ（ATP）"
        let document = DocumentParseResult(format: .pdf, blocks: [
            .init(kind: .paragraph, text: source, readingOrder: 0)
        ], warnings: [])
        let terms = ["금속제(시스형", "시스형)온도계", "[14C", "Fe(OH)3", "[14C]glucose", "ＡＴＰ（ATP）"]
        XCTAssertEqual(try ProtocolDocumentTermCleaner.clean(terms, document: document),
                       ["금속제(시스형)온도계", "[14C]glucose", "Fe(OH)3", "ＡＴＰ（ATP）"])
    }

    func testKoreanParticlesDoNotDuplicateSelectedNamesOrPromoteBrokenFinalSyllables() throws {
        let document = DocumentParseResult(format: .pdf, blocks: [
            .init(kind: .paragraph,
                  text: "아세트산 증기가 발생한다. 아스피린 결정을 얻는다. 아세틸 기를 확인한다.",
                  readingOrder: 0)
        ], warnings: [])
        let terms = ["아세트산 증기", "아세트산 증기가", "아스피린 결", "아세틸 기"]
        XCTAssertEqual(try ProtocolDocumentTermCleaner.clean(terms, document: document),
                       ["아세트산 증기", "아세틸 기"])
    }

    func testAspirinParagraphAndIndependentPageBoundaries() throws {
        // 실제 아스피린 합성실험 PDF의 본문 발췌.
        let document = DocumentParseResult(format: .pdf, blocks: [
            .init(kind: .paragraph,
                  text: "아스피린(Aspirin) 또는 아세틸 살리실산(acetylsalicylic acid, ASA)은",
                  readingOrder: 0, location: .init(page: 1)),
            .init(kind: .paragraph, text: "살리실산염 의약품.",
                  readingOrder: 1, location: .init(page: 2))
        ], warnings: [])
        let terms = ["아스피린(Aspirin)", "아스피린", "Aspirin", "아세틸 살리실산",
                     "ASA)은\n살리실산염", "살리실산염"]
        XCTAssertEqual(try ProtocolDocumentTermCleaner.clean(terms, document: document),
                       ["아스피린(Aspirin)", "아스피린", "Aspirin", "아세틸 살리실산", "살리실산염"])
    }

    func testCellsOCRChemicalsAndIncompleteFragments() throws {
        let document = DocumentParseResult(format: .pdf, blocks: [
            .init(kind: .tableCell, text: "강수량계", readingOrder: 0,
                  location: .init(page: 1, row: 1, column: 1)),
            .init(kind: .tableCell, text: "습도계", readingOrder: 1,
                  location: .init(page: 1, row: 1, column: 2)),
            .init(kind: .imageOCR, text: "C9H8O4 + H2O → C7H6O3", readingOrder: 2,
                  location: .init(page: 2)),
            .init(kind: .paragraph, text: "pH R. Wm? R.H", readingOrder: 3)
        ], warnings: [])
        let terms = ["강수량계", "수량", "강수량계\n습도계", "습도계", "C9H8O4",
                     "H2O", "C7H6O3", "pH", "R.", "Wm?", "R.H"]
        XCTAssertEqual(try ProtocolDocumentTermCleaner.clean(terms, document: document),
                       ["강수량계", "습도계", "C9H8O4", "H2O", "C7H6O3", "pH", "R.H"])
    }

    func testAspirinListSeparatesItemsButKeepsChemicalLocantsAndParentheses() throws {
        // 아스피린 합성실험 PDF의 실험기구·시약 목록 발췌.
        let source = "피펫(Pipette), 깔때기(Funnel), 가열교반기(Hot plate), "
            + "살리실산(salicylic acid), 1,2-dichloroethane; N,N-dimethylformamide"
        let document = DocumentParseResult(format: .pdf, blocks: [
            .init(kind: .paragraph, text: source, readingOrder: 0)
        ], warnings: [])
        let terms = ["가열교반기(Hot plate), 살리실산(salicylic acid)",
                     "1,2-dichloroethane; N,N-dimethylformamide"]
        XCTAssertEqual(try ProtocolDocumentTermCleaner.clean(terms, document: document), [
            "가열교반기(Hot plate)", "살리실산(salicylic acid)",
            "1,2-dichloroethane", "N,N-dimethylformamide"
        ])
    }

    func testWeatherCompositeAndOverlappingParenthesisFragment() throws {
        // 기상측기의 검정방법 PDF 본문 발췌.
        let document = DocumentParseResult(format: .pdf, blocks: [
            .init(kind: .paragraph,
                  text: "금속제(시스형)온도계 검정점 및 기압계(기계식_액주형)", readingOrder: 0)
        ], warnings: [])
        let terms = ["금속제(시스형)온도계", "(시스형)온도계", "기계식_액주형"]
        XCTAssertEqual(try ProtocolDocumentTermCleaner.clean(terms, document: document),
                       ["금속제(시스형)온도계", "기압계(기계식_액주형)"])
    }

    func testAmbiguousCompositeIsNotExpanded() throws {
        let document = DocumentParseResult(format: .pdf, blocks: [
            .init(kind: .paragraph,
                  text: "기압계(기계식_액주형)와 풍속계(기계식_액주형), 기계식 풍향계",
                  readingOrder: 0)
        ], warnings: [])
        XCTAssertEqual(try ProtocolDocumentTermCleaner.clean(
            ["기계식_액주형", "기계식"], document: document
        ), ["기계식_액주형", "기계식"])
    }

    func testOCRReactionBoundariesWithoutDiscardingChemicalFormulaOrWrappedLine() throws {
        let source = "C9H8O4 + H2O → C7H6O3\nCH3COOH + NaOH → CH3COONa + H2O"
        let document = DocumentParseResult(format: .pdf, blocks: [
            .init(kind: .imageOCR, text: source, readingOrder: 0)
        ], warnings: [])
        let terms = [source, "C9H8O4", "CH3COOH", "C9H8O4 + H2O → C7H6O3"]
        XCTAssertEqual(try ProtocolDocumentTermCleaner.clean(terms, document: document),
                       ["C9H8O4", "CH3COOH", "C9H8O4 + H2O → C7H6O3"])
    }

    func testPercentKeepsConcentrationAndUnitsAndDoesNotCreateMissingNumbers() throws {
        let source = "85% 인산 70%에탄올 % 인산 %R.H. % 수득률(%) 에탄올(70%, v/v)"
        let document = DocumentParseResult(format: .pdf, blocks: [
            .init(kind: .paragraph, text: source, readingOrder: 0)
        ], warnings: [])
        let terms = ["85% 인산", "70%에탄올", "% 인산", "%R.H.", "%",
                     "수득률(%)", "에탄올(70%, v/v)"]
        XCTAssertEqual(try ProtocolDocumentTermCleaner.clean(terms, document: document), [
            "85% 인산", "70%에탄올", "%R.H.", "%", "수득률(%)", "에탄올(70%, v/v)"
        ])
    }

    func testMissingConcentrationIsRestoredOnlyWhenEveryOccurrenceAgrees() throws {
        let source = "85% 인산; 85% 인산; 70%에탄올; 50%에탄올; ８５％ 인산"
        let document = DocumentParseResult(format: .pdf, blocks: [
            .init(kind: .paragraph, text: source, readingOrder: 0)
        ], warnings: [])
        XCTAssertEqual(try ProtocolDocumentTermCleaner.clean(
            ["% 인산", "%에탄올", "８５％ 인산"], document: document
        ), ["85% 인산", "８５％ 인산"])
    }

    func testBracketRestorationCannotChooseBetweenDifferentCompleteNames() throws {
        let source = "풍속계(기계식)와 풍속계(기계식_지시형), 온도계(유리제)"
        let document = DocumentParseResult(format: .pdf, blocks: [
            .init(kind: .paragraph, text: source, readingOrder: 0)
        ], warnings: [])
        XCTAssertEqual(try ProtocolDocumentTermCleaner.clean(
            ["풍속계(기계식", "온도계(유리제"], document: document
        ), ["온도계(유리제)"])
    }

    func testBracketRestorationDoesNotCrossBlocksOrSplitBracketedLists() throws {
        let document = DocumentParseResult(format: .pdf, blocks: [
            .init(kind: .paragraph, text: "풍속계(기계식", readingOrder: 0),
            .init(kind: .paragraph, text: ")", readingOrder: 1),
            .init(kind: .paragraph, text: "표준물질[A, B], 시약{C, D}", readingOrder: 2)
        ], warnings: [])
        XCTAssertEqual(try ProtocolDocumentTermCleaner.clean(
            ["풍속계(기계식", "표준물질[A, B], 시약{C, D}"], document: document
        ), ["표준물질[A, B]", "시약{C, D}"])
    }

    func testCompleteBracketNameDoesNotAbsorbFollowingKoreanParticle() throws {
        let source = "아스피린(Aspirin)은 아세틸살리실산(acetylsalicylic acid)을 뜻한다."
        let document = DocumentParseResult(format: .pdf, blocks: [
            .init(kind: .paragraph, text: source, readingOrder: 0)
        ], warnings: [])
        XCTAssertEqual(try ProtocolDocumentTermCleaner.clean(
            ["아스피린(Aspirin)", "아세틸살리실산(acetylsalicylic acid)"], document: document
        ), ["아스피린(Aspirin)", "아세틸살리실산(acetylsalicylic acid)"])
    }

    func testChangedDocumentTextCannotUseStaleBlockOffsets() {
        var document = DocumentParseResult(format: .pdf, blocks: [
            .init(kind: .paragraph, text: "기상측기", readingOrder: 0)
        ], warnings: [])
        document.fullText = "다른 본문"
        XCTAssertThrowsError(try ProtocolDocumentTermCleaner.clean(["기상측기"], document: document))
    }
}
