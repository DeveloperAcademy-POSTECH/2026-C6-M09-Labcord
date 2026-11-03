import Foundation
@testable import LabcordiOS
import XCTest

final class ProtocolTimerExtractorTests: XCTestCase {
    func testCapitalPhysicalSymbolsDoNotBecomeMinutesHoursOrSeconds() {
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "5 M NaCl, 2 H2O, 70 S"), [])
        XCTAssertFalse(ProtocolTimerExtractor.needsManualReview(in: "1~5 M NaCl"))
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "2 HOUR, 5 MIN, 30 SEC"),
                       [7_200, 300, 30])
    }

    func testWindSpeedDoesNotProduceScreenshotTimers() {
        let text = """
            1.0 m/s, 5 m/s, 1.0 m/s, 1.0 m/s,
            70 m/s, 70 m/s, 1.0 m/s, 70 m/s
            """
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: text), [])
    }

    func testCompoundPhysicalUnitsAreNotDurations() {
        let values = [
            "1 m/h", "2 mm/h", "3 ㎜/h", "4 m²", "5 m^2", "6 m·s^-1",
            "7 s^-1", "8 s⁻¹", "9 s/min", "10 m / s", "11 mm²", "12 m2", "13 m s⁻¹"
        ]
        for value in values {
            XCTAssertEqual(ProtocolTimerExtractor.extract(from: value), [], value)
        }
    }

    func testKoreanAndEnglishCompactDurations() {
        let values: [(String, [Int])] = [
            ("1시간10분", [4_200]), ("1분30초", [90]),
            ("1h30m", [5_400]), ("5m30s", [330]),
            ("30초간 가열", [30]), ("1.5분 냉각", [90]),
            ("5 min", [300]), ("30 sec", [30])
        ]
        for (text, expected) in values {
            XCTAssertEqual(ProtocolTimerExtractor.extract(from: text), expected, text)
        }
    }

    func testCompoundDurationsDoNotJoinAcrossLinesOrRestartedUnits() {
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "1분 30초\n2분 10초"), [90, 130])
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "1분 30초 2분 10초"), [90, 130])
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "1시간\n10분"), [3_600, 600])
    }

    func testEquivalentDurationsKeepFirstOccurrenceOrder() {
        let text = "30초; 1시간10분; 70분; 1분; 60초; 1시간 10분; 30 sec"
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: text), [30, 4_200, 60])
    }

    func testKoreanWordBoundariesAndRatesAreNotDurations() {
        let values = [
            "1분석 시료", "1분당 60회", "1시간당 3회", "60분/시간당",
            "10m 길이", "1분의 오차", "A10s", "70S protein", "5ml 3ms"
        ]
        for value in values {
            XCTAssertEqual(ProtocolTimerExtractor.extract(from: value), [], value)
        }
    }

    func testRangesAreNotConvertedToFixedTimers() {
        let values = [
            "10~20분", "10분~20분", "10 to 20 min", "0.5min-1min",
            "1시간10분~2시간20분", "10분에서20분", "10분부터20분까지"
        ]
        for value in values {
            XCTAssertEqual(ProtocolTimerExtractor.extract(from: value), [], value)
        }
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "10~20분 후 30초 가열"), [30])
    }

    func testDurationRangesRequireManualReviewWithoutFixedTimers() {
        let values = [
            "10~20분", "10분~20분", "10 to 20 min", "0.5min-1min",
            "1시간10분~2시간20분", "10분에서20분", "10분부터20분까지"
        ]
        for value in values {
            XCTAssertTrue(ProtocolTimerExtractor.needsManualReview(in: value), value)
            XCTAssertEqual(ProtocolTimerExtractor.extract(from: value), [], value)
        }
    }

    func testConditionalDurationsKeepTheirMeaningForManualReview() {
        let values = [
            "1분이상", "5초 이내", "1분30초이상", "1분이상교반", "2시간 이하",
            "10분 미만", "5초 초과", "약 1분", "최소5분", "최대 30초", "1분 정도",
            "at least 1 min", "up to 5 seconds", "less than 10 min", "about 5m",
            "2 min or more", "10 seconds or less", "AT MOST 1 hour"
        ]
        for value in values {
            XCTAssertTrue(ProtocolTimerExtractor.needsManualReview(in: value), value)
            XCTAssertEqual(ProtocolTimerExtractor.extract(from: value), [], value)
        }
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "1분 이상 교반 후 30초 냉각"), [30])
    }

    func testPhysicalRangesAndRateConditionsDoNotRequireTimerReview() {
        let values = [
            "1~5m/s", "10~20m/h", "1~5㎜/h", "1~5ms", "1~5m²",
            "at least 5m/s", "up to 20m/h", "5m/s이상", "1분당 60회", "1분석 시료"
        ]
        for value in values {
            XCTAssertFalse(ProtocolTimerExtractor.needsManualReview(in: value), value)
            XCTAssertEqual(ProtocolTimerExtractor.extract(from: value), [], value)
        }
    }

    func testDefiniteDurationsRemainAutomaticWithoutReviewWarning() {
        let text = "1분간 교반; 5초후 냉각; 1분30초 가열; 10 min"
        XCTAssertFalse(ProtocolTimerExtractor.needsManualReview(in: text))
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: text), [60, 5, 90, 600])
        XCTAssertFalse(ProtocolTimerExtractor.needsManualReview(in: "시약1분간 교반"))
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "시약1분간 교반"), [60])
    }

    func testClockTimesAndOriginalVolumeGuardsRemainExcluded() {
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "01:02:03 유지"), [3_723])
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "오전 01:02:03 기록"), [])
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "-5분; 10mL; 3ms"), [])
    }

    func testExplicitLengthMDoesNotBecomeMinutesOrDurationReview() {
        let values = [
            "길이 10m", "높이는 5 m", "깊이: 3m", "length of 2m", "depth = 4 m",
            "5m long", "5m in height", "5m 깊이", "높이 1~5m", "about 5m deep"
        ]
        for text in values {
            XCTAssertEqual(ProtocolTimerExtractor.extract(from: text), [], text)
            XCTAssertFalse(ProtocolTimerExtractor.needsManualReview(in: text), text)
        }
    }

    func testLengthAndFollowingMinuteDurationRemainIndependent() {
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "길이 10m를 잘라 5 min 동안 배양"), [300])
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "길이 10cm, incubate for 5m"), [300])
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "길이 10m, incubate for 5m"), [300])
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "Incubate for 5 m"), [300])
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "5m30s"), [330])
        XCTAssertEqual(ProtocolTimerExtractor.extract(from: "5m 동안 배양"), [300])
        XCTAssertTrue(ProtocolTimerExtractor.needsManualReview(in: "about 5m incubation"))
    }
}
