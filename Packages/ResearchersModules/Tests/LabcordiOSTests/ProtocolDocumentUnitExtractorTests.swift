import Foundation
@testable import LabcordiOS
import XCTest

final class ProtocolDocumentUnitExtractorTests: XCTestCase {
    func testElectricalAndSubsecondMeasurementUnitsDoNotBecomeTimers() {
        let source = "RC 회로: R=1 kΩ, C=100 µF, L=20mH, 지연10ms, 펄스2µs, 3ns."
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: source),
                       ["kΩ", "µF", "mH", "ms", "µs", "ns"])
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: source), [])
        XCTAssertEqual(ProtocolTermNormalizer.key("uF"), ProtocolTermNormalizer.key("µF"))
        XCTAssertEqual(ProtocolTermNormalizer.key("uH"), ProtocolTermNormalizer.key("µH"))
    }

    func testChemicalFormulasAndFigureLabelsDoNotBecomeElectricalUnits() {
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(
            from: "C6H6 + H2O + HF. Figure 2F, METHOD 20H."
        ), [])
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(
            from: "capacitance (F), inductance (H), resistance (Ω)"
        ), ["F", "H", "Ω"])
    }

    func testOCRReagentFragmentsDoNotBecomeHighOrderElectricalUnits() {
        // 실제 아스피린 PDF의 증류수 OCR 조각과 명시적인 수학 표기를 구분합니다.
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(
            from: "Li(phosphoric acid), 5 F7(distilled water), 증류수(distilled water)"
        ), [])
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(
            from: "1 F^-1; 2 F-1; 3 F⁻¹; 4 F^7; 5 F⁷; 6 W/m2; 7 kg/m3; 8 m/s2"
        ), ["F^-1", "F-1", "F⁻¹", "F^7", "F⁷", "W/m2", "kg/m3", "m/s2"])
    }

    func testAttachedHydrogenAndOHOCRRequireElectricalMeasurementContext() {
        // 완충용액 PDF의 OH를 0H로 읽은 구절을 헨리로 보충하지 않습니다.
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(
            from: "혈액 속에 0H\n혈액 속에 녹아 들어가더라도. 2H + 2F → 2HF."
        ), [])
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(
            from: "20mH; 100µF; 1 H; capacitance10F; L=2H; C=3F; inductance4H"
        ), ["mH", "µF", "H", "F"])
    }

    func testAspirinMeasurementsAreRecoveredWithoutSelectingTheirNumbers() {
        let source = """
            바이엘 아스피린, 500mg
            F.W: 102.9g/mol
            d: 1.082g/mL
            살리실산 1.0g을 삼각플라스크에 넣고 아세트산 무수물 3mL를 넣는다.
            85% 인산 3~4 방울을 넣고 70~85°C로 유지하여 10분간 가열한다.
            수득률(%) = 얻은 질량 / 이론적인 질량
            """
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: source),
                       ["mg", "g/mol", "g/mL", "g", "mL", "%", "°C"])
    }

    func testWeatherCompoundsAndHumidityKeepTheirActualNotation() {
        let source = """
            마지막 자리는 0.1
            W/m2로 한다. 검정점은 60 ℃이며 중간점(°C)을 검정한다.
            습도계는 30, 60, 90 %R.H.이며 풍속 1.0 m/s로 한다.
            검정점의 R.H.를 기록하고 풍향은 360°를 16방위로 검정한다.
            """
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: source),
                       ["W/m2", "℃", "%R.H.", "m/s", "R.H.", "°"])
    }

    func testSICompoundFormsMicroAndWidthVariants() {
        let source = "2 W/m²; 3 W/m2; 4 μL; 5 µL; 6 m·s⁻¹; 7 m s^-1; 8 kg/m³; 9 ㎖"
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: source),
                       ["W/m²", "μL", "m·s⁻¹", "m s^-1", "kg/m³", "㎖"])
    }

    func testUnitCaseIsNotFoldedBetweenLengthAndConcentration() {
        let source = "2 mm; 3 mM; 4 M; 5 mol/L; pH 7.4; OD600 0.5"
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: source),
                       ["mm", "mM", "M", "mol/L", "pH", "OD600"])
    }

    func testPercentNotationsAndConcentrationNamesAreSeparate() {
        let source = "70%에탄올, 100%ethanol, 10%(v/v) DMSO, 20% (w/v)"
        let terms = ProtocolExtractedTerms(materials: ["70%에탄올", "DMSO"],
                                          glossaryTerms: ["에탄올"])
        let result = ProtocolDocumentUnitExtractor.supplement(terms, from: source)
        XCTAssertEqual(result.materials, ["70%에탄올", "DMSO"])
        XCTAssertEqual(result.glossaryTerms, ["에탄올"])
        XCTAssertEqual(result.units, ["%", "%(v/v)", "% (w/v)"])
    }

    func testDurationsNamesAndBrokenOCRAreNotInventedAsUnits() {
        let source = """
            Add DMSO and NaCl for 10 min, 30 s, and 1 h.
            COOH + H2O → CH3COOH. R. Wm? 70S protein 3ms
            살리실산(salicylic acid), 자동적설계, 검정
            """
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: source), ["ms"])
    }

    func testSupplementMovesOnlyExactUnitTermsAndPreservesFallbackAndOrder() {
        let terms = ProtocolExtractedTerms(
            materials: ["살리실산", "mL"], samples: ["시료"],
            glossaryTerms: ["W/m²", "교반"], units: ["°C", "μL"], usedFallback: true
        )
        let result = ProtocolDocumentUnitExtractor.supplement(
            terms, from: "2 mL의 시료, 70 ℃, 1 µL, 일사 0.1 W/m2"
        )
        XCTAssertEqual(result.materials, ["살리실산"])
        XCTAssertEqual(result.samples, ["시료"])
        XCTAssertEqual(result.glossaryTerms, ["교반"])
        XCTAssertEqual(result.units, ["°C", "μL", "mL", "W/m2"])
        XCTAssertTrue(result.usedFallback)
    }

    func testCompoundUnitsAreClassifiedAsUnitsWithoutChangingChemicalCase() {
        for unit in ["m/s", "W/m²", "%R.H.", "R.H.", "kg/m³", "µL", "°C", "rpm"] {
            XCTAssertTrue(ProtocolTermNormalizer.isUnit(unit), unit)
        }
        for term in ["Wm?", "R.", "NaCl", "COOH", "살리실산", "기압계"] {
            XCTAssertFalse(ProtocolTermNormalizer.isUnit(term), term)
        }
    }

    func testCompletedClassificationSupplementsUnitsWithoutRepeatingCheckpoint() async throws {
        let seed = ProtocolExtractedTerms(materials: ["아스피린"])
        let result = try await ProtocolTermClassifier.classifyDocument(
            ["아스피린"], context: "아스피린을 3mL에 넣고 10분간 가열한다.", seed: seed
        ) { _ in XCTFail("A completed prefix must not be classified again") }
        XCTAssertEqual(result.materials, ["아스피린"])
        XCTAssertEqual(result.units, ["mL"])
        XCTAssertFalse(result.usedFallback)
    }

    func testStandaloneMRequiresAnExplicitLengthContext() {
        let physical = [
            "길이 10m", "높이는 5 m", "깊이: 3m", "너비 1~5m", "length of 2m",
            "depth = 4 m", "5m long", "5m in height", "5m 깊이", "높이(m)", "단위 [m]"
        ]
        for source in physical {
            XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: source), ["m"], source)
        }
        let durations = [
            "Incubate for 5 m", "Wait 5m", "5m 동안 배양", "5m", "5m30s", "5m for incubation"
        ]
        for source in durations {
            XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: source), [], source)
        }
    }

    func testLengthContextDoesNotLeakAcrossAnotherDurationOrClause() {
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: "길이 10cm, incubate for 5m"),
                       ["cm"])
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: "길이 10m, incubate for 5m"),
                       ["m"])
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: "배양 후 길이 10m를 측정"),
                       ["m"])
    }

    func testBufferEquationSymbolsDoNotBecomeMeasurements() {
        // 실제 완충용액 PDF의 OCR 수식·농도 변수·읽기자료 발췌.
        let source = """
            (CH3)3NH+/(CH3)3N
            (CH3)зNH+/(CH3)зN
            DH~ Dk.- l08 TA]0
            pH = pK. - 108 TA-lo
            두 값은 [HA]와 [A] o에 비하여 작다.
            높이가 3km 정도 되는 산을 이틀 만에 올라간다.
            0.1M 아세트산 수용액 50mL를 비커에 넣는다.
            순수한 물 1L의 pH를 측정한다.
            """
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: source),
                       ["pH", "km", "M", "mL", "L"])
    }

    func testConductanceMethodIdentifiersAndVariablesAreNotUnitHeaders() {
        // 실제 METHOD 9050A PDF의 문서 번호·계산 변수·표준 용액 발췌.
        let source = """
            METHOD 9050A
            CD-ROM 9050A - 1 Revision 1
            K = conductivity
            (K )(1,000,000)(C)
            of 0.01 N KCl solution.
            """
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: source), ["N"])
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: "(A) [N] (K)"), [])
    }

    func testElectricalUnitsKeepSiemensAndActualMhoNotations() {
        // 같은 전도도 PDF가 단위 설명과 표 머리글에서 수치 없이 사용하는 표기입니다.
        let source = """
            where: Km = measured conductivity, uS at t°C
            When sample conductivity is measured, conductivity at 25°C is:
            conductivity is reported as millisiemens per meter (mS/m);
            mS/m = 10 umhos/cm and 1 uS/cm = 1 umho/cm.
            mS/m = 10 µmhos/cm and 1 µS/cm = 1 µmho/cm.
            siemens (S)
            uS/cm Results % %
            """
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: source), [
            "uS", "°C", "mS/m", "umhos/cm", "uS/cm", "S", "%"
        ])
    }

    func testRealHeadersKeepCommonUnitsWithoutTreatingChemicalBracketsAsHeaders() {
        let source = """
            concentration (mM)
            volume [mL]
            mg
            current (A)
            normality (N)
            temperature (K)
            """
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: source),
                       ["mM", "mL", "mg", "A", "N", "K"])
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: "3A; 1e3 A; 0.01 N"),
                       ["A", "N"])
    }

    func testComparisonKeysPreserveScaleAndPhysicalUnitCase() {
        XCTAssertEqual(Set(["mM", "mm", "M", "m"].map(ProtocolTermNormalizer.key)).count, 4)
        XCTAssertNotEqual(ProtocolTermNormalizer.key("mPa"), ProtocolTermNormalizer.key("MPa"))
        XCTAssertNotEqual(ProtocolTermNormalizer.key("mA"), ProtocolTermNormalizer.key("MA"))
        XCTAssertNotEqual(ProtocolTermNormalizer.key("mL"), ProtocolTermNormalizer.key("ML"))
        XCTAssertEqual(ProtocolTermNormalizer.key(" ＡＳＰＩＲＩＮ "),
                       ProtocolTermNormalizer.key("aspirin"))
        XCTAssertEqual(ProtocolTermNormalizer.key("아스피린(Aspirin)"),
                       ProtocolTermNormalizer.key("아스피린(ASPIRIN)"))
    }

    func testComparisonKeysNormalizeMicroAndLitreOnlyAtUnitBoundaries() {
        for variant in ["uS/cm", "µS/cm", "μS / cm"] {
            XCTAssertEqual(ProtocolTermNormalizer.key(variant), "μS/cm", variant)
        }
        for variant in ["ul", "uL", "µl", "μL", "㎕"] {
            XCTAssertEqual(ProtocolTermNormalizer.key(variant), "μL", variant)
        }
        for variant in ["ml", "mL", "ｍＬ", "㎖"] {
            XCTAssertEqual(ProtocolTermNormalizer.key(variant), "mL", variant)
        }
        XCTAssertEqual(ProtocolTermNormalizer.key("ug/ml"), "μg/mL")
        XCTAssertEqual(ProtocolTermNormalizer.key("mg/ul"), "mg/μL")
        XCTAssertEqual(ProtocolTermNormalizer.key("umol/ml"), "μmol/mL")
        XCTAssertEqual(ProtocolTermNormalizer.key("nmol/L"), "nmol/L")
        XCTAssertEqual(ProtocolTermNormalizer.key("mol"), "mol")
        XCTAssertEqual(ProtocolTermNormalizer.key("W/m²"), ProtocolTermNormalizer.key("W/m2"))
    }

    func testUnitAliasesDeduplicateWhileKeepingFirstSourceSpellingAndDifferentScales() {
        let source = "1 uS/cm; 2 µS/cm; 3 ml; 4 mL; 5 ul; 6 µL; 7 mM; 8 mm; 9 M"
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: source),
                       ["uS/cm", "ml", "ul", "mM", "mm", "M"])
        let terms = ProtocolExtractedTerms(units: ["µS/cm", "mL", "μL"])
        let result = ProtocolDocumentUnitExtractor.supplement(terms, from: source)
        XCTAssertEqual(result.units, ["µS/cm", "mL", "μL", "mM", "mm", "M"])
    }

}

extension ProtocolDocumentUnitExtractorTests {
    func testOhmNamesKeepTheFirstActualSpellingWithoutAcceptingNamesOrMetadata() {
        let source = "Rm = measured resistance of sample, ohms; the reciprocal of the ohm. 1 Ω"
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: source), ["ohms"])
        for unit in ["ohm", "ohms", "Ω", "Ω"] {
            XCTAssertEqual(ProtocolTermNormalizer.key(unit), "Ω", unit)
        }
        XCTAssertNotEqual(ProtocolTermNormalizer.key("Ohm"), ProtocolTermNormalizer.key("ohm"))
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(
            from: "Ohm's law; ohmic; rheohms; AUTHOR: ohm\nMODEL ohm\nMETHOD 9050ohms"
        ), [])
    }

    func testMhoPluralAliasesKeepTheirPrefixesAndFirstSourceSpelling() {
        XCTAssertEqual(ProtocolTermNormalizer.key("µmhos/cm"),
                       ProtocolTermNormalizer.key("μmho/cm"))
        XCTAssertNotEqual(ProtocolTermNormalizer.key("mhos"), ProtocolTermNormalizer.key("mmhos"))
        XCTAssertNotEqual(ProtocolTermNormalizer.key("mho"), ProtocolTermNormalizer.key("siemens"))
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(
            from: "1 mhos; 2 mho; 3 mmhos; 4 mmho; 5 µmhos/cm; 6 µmho/cm"
        ), ["mhos", "mmhos", "µmhos/cm"])
    }

    func testWeatherPressureRecoversHectopascalsFromActualSource() {
        let source = """
            실내검정 검정점은 800, 850, 900, 950, 980, 1010, 1040
            hPa로 하며, 현장검정은 실황 3회를 비교하여 검정한다.
            실내검정의 검정점은 950, 980, 1010, 1040 hPa이다.
            """
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: source), ["hPa"])
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: source), [])
    }

    func testHectoUnitsDoNotAcceptIdentifiersOrBecomeHours() {
        let source = "METHOD 9050hPa; Model 1040hPa; sample1040hPa; 1040hPa에서 2h 동안 측정"
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: source), ["hPa"])
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: source), [7_200])
        XCTAssertTrue(ProtocolTermNormalizer.isUnit("hPa"))
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: "METHOD 9050hPa"), [])
    }

    func testHectolitreComparisonKeepsTheFirstActualSpelling() {
        XCTAssertEqual(ProtocolTermNormalizer.key("hl"), ProtocolTermNormalizer.key("hL"))
        XCTAssertEqual(ProtocolDocumentUnitExtractor.extract(from: "1 hl; 2 hL; 3 hPa"),
                       ["hl", "hPa"])
    }

    func testConfirmedNonUnitLabelsMoveToGlossaryWithoutLosingTermsOrOrder() {
        let source = """
            where:
            Km = measured conductivity, uS at t°C
            Rm = measured resistance of sample, ohms
            CD-ROM 9050A - 1
            [H,0+]
            """
        let terms = ProtocolExtractedTerms(
            glossaryTerms: ["교반"],
            units: ["Km", "siemens", "0+", "Rm", "ROM", "millisiemens", "μL"]
        )
        let result = ProtocolDocumentUnitExtractor.supplement(terms, from: source)
        XCTAssertEqual(result.glossaryTerms, ["교반", "Km", "0+", "Rm", "ROM"])
        XCTAssertEqual(result.units, ["siemens", "millisiemens", "μL", "uS", "ohms"])
        XCTAssertTrue(Set(terms.all).isSubset(of: Set(result.all)))
        XCTAssertTrue(result.usedFallback)
    }

    func testKnownSymbolsAndUnrecognizedUnitNamesKeepModelLabels() {
        let units = ["siemens", "millisiemens", "ohm", "knot", "tesla", "mM", "mm", "K"]
        let source = "K = measured temperature. Units: siemens, millisiemens, ohm, knot, tesla."
        let result = ProtocolDocumentUnitExtractor.supplement(
            ProtocolExtractedTerms(units: units), from: source
        )
        XCTAssertEqual(result.units, units)
        XCTAssertEqual(result.glossaryTerms, [])
        XCTAssertFalse(result.usedFallback)
    }

    func testDocumentFragmentNeedsEveryOccurrenceInsideTheIdentifier() {
        let result = ProtocolDocumentUnitExtractor.supplement(
            ProtocolExtractedTerms(units: ["ROM"]),
            from: "CD-ROM 9050A. ROM은 별도 장치의 명칭이다."
        )
        XCTAssertEqual(result.units, ["ROM"])
        XCTAssertEqual(result.glossaryTerms, [])
        XCTAssertFalse(result.usedFallback)
    }

    func testCelsiusOCRNeedsMatchingOriginalReadingsAndDoesNotTranslateTerms() {
        let source = """
            at 25°C.
            at 25EC.
            nearest 0.1°C.
            nearest 0.1EC.
            measured conductivity, uS at t°C
            measured conductivity, uS at tEC
            t = observed temperature, °C.
            t = observed temperature, EC.
            """
        let result = ProtocolDocumentUnitExtractor.supplement(
            ProtocolExtractedTerms(glossaryTerms: ["교반"], units: ["EC", "tEC", "siemens"]),
            from: source
        )
        XCTAssertEqual(result.glossaryTerms, ["교반", "EC", "tEC"])
        XCTAssertEqual(result.units, ["siemens", "°C", "uS"])
        XCTAssertTrue(result.usedFallback)
    }

    func testAmbiguousCelsiusOCRKeepsClassificationAndRequestsReview() {
        let result = ProtocolDocumentUnitExtractor.supplement(
            ProtocolExtractedTerms(units: ["EC", "tEC"]),
            from: "25EC; 30°C; tEC."
        )
        XCTAssertEqual(result.units, ["EC", "tEC", "°C"])
        XCTAssertEqual(result.glossaryTerms, [])
        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(ProtocolDocumentUnitExtractor.supplement(
            ProtocolExtractedTerms(units: ["EC"]), from: "25EC"
        ).units, ["EC"])
    }

    func testReclassificationAndUnitSupplementDoNotDuplicateExistingTerms() {
        let source = "Km = measured conductivity. 1 uS/cm; 2 µS/cm; 3 μS/cm."
        let result = ProtocolDocumentUnitExtractor.supplement(
            ProtocolExtractedTerms(glossaryTerms: ["Km", "교반"], units: ["Km", "µS/cm"]),
            from: source
        )
        XCTAssertEqual(result.glossaryTerms, ["Km", "교반"])
        XCTAssertEqual(result.units, ["µS/cm"])
        XCTAssertTrue(result.usedFallback)
    }
}
