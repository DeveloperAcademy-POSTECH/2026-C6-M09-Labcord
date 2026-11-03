import Foundation
import FoundationModels
@testable import LabcordiOS
import LabcordShared
import XCTest

final class R117PipelineTests: XCTestCase {
    private let source = "Add sodium chloride to phosphate buffer and centrifuge for 5 min."

    @MainActor
    func testParsedProtocolRoundTripPreservesSpeechHints() async throws {
        let identifier = UUID()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("protocol-\(identifier).txt")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let parsed = try await ProtocolAnalysisClient.liveValue.parse(
            [ProtocolAnalysisInput(id: identifier, url: url)], nil
        )
        let text = try XCTUnwrap(parsed.first?.extractedText)
        let terms = try await ProtocolTermClient.liveValue.extract(text)
        XCTAssertFalse(terms.isEmpty)
        print("Foundation Model availability: \(SystemLanguageModel.default.availability)")
        print("Foundation Model fallback used: \(terms.usedFallback)")
        if SystemLanguageModel.default.isAvailable {
            XCTAssertFalse(terms.usedFallback, "Classification included fallback labels")
        }
        for term in terms.all { XCTAssertTrue(text.contains(term)) }
        let timers = ProtocolTimerExtractor.extract(from: text)
        XCTAssertEqual(timers, [300])
        let client = ExperimentClient.liveValue
        let experiment = ExperimentProtocol(
            timerSeconds: timers, materials: terms.materials, samples: terms.samples,
            glossaryTerms: terms.glossaryTerms, units: terms.units
        )
        _ = try client.createWithProtocol(identifier, .now, "Simulator protocol QA", experiment)
        defer { try? client.delete(identifier) }
        let detail = try XCTUnwrap(client.loadDetail(identifier))
        XCTAssertEqual(Set(detail.speechContextualStrings), Set(terms.all))
        XCTAssertEqual(detail.timerSeconds, timers)
    }

    func testExtractionTimeAndMemory() {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            let finished = expectation(description: "R117 extraction")
            Task {
                do {
                    let terms = try await R117TermExtractor.shared.extract(from: source)
                    XCTAssertFalse(terms.isEmpty)
                } catch {
                    XCTFail("Extraction failed: \(error)")
                }
                finished.fulfill()
            }
            wait(for: [finished], timeout: 120)
        }
    }
}

extension R117PipelineTests {
    func testMergedRecordsPreserveLegacyTwoPassValuesAndOrder() throws {
        let text = "sodium chloride와 인산(85%) · μL"
        let scalars = Array(text.unicodeScalars)
        let merged = try [
            mergedCandidate("sodium chloride", text: text, score: 0.125, kind: "pool", tier: 1),
            mergedCandidate("odium", text: text, score: -0.0, kind: "ngram", tier: 2),
            mergedCandidate("인산(85%)", text: text, score: .leastNonzeroMagnitude,
                            kind: "cleanvar", tier: 3),
            mergedCandidate("85%", text: text, score: .greatestFiniteMagnitude,
                            kind: "charngram", tier: 2),
            mergedCandidate("·", text: text, score: 0.3, kind: "pool", tier: 1),
            mergedCandidate("μL", text: text, score: 0.5, kind: "word", tier: 1),
            mergedCandidate("odium", text: text, score: 0.75, kind: "oligo", tier: 1,
                            noFilter: true),
            mergedCandidate("인산(85%)", text: text, score: -0.25, kind: "wsnap", tier: 2)
        ]
        for language in ["ko", "en"] {
            let expected = try legacyRecords(merged: merged, scalars: scalars, language: language)
            let actual = try R117NativeCandidatePool.records(
                merged: merged, scalars: scalars, language: language
            )
            XCTAssertEqual(actual.raw.count, merged.count)
            XCTAssertEqual(actual.raw.map { [$0.start, $0.end, $0.tier] },
                           expected.raw.map { [$0.start, $0.end, $0.tier] })
            XCTAssertEqual(actual.raw.map(\.score.bitPattern),
                           expected.raw.map(\.score.bitPattern))
            XCTAssertEqual(actual.raw.map(\.kind), expected.raw.map(\.kind))
            XCTAssertEqual(actual.raw.map(\.retained), expected.raw.map(\.retained))
            XCTAssertEqual(actual.cached.map { [$0.start, $0.end] },
                           expected.cached.map { [$0.start, $0.end] })
            XCTAssertEqual(actual.cached.map(\.score.bitPattern),
                           expected.cached.map(\.score.bitPattern))
            XCTAssertEqual(actual.cached.map(\.admitted), expected.cached.map(\.admitted))
            XCTAssertEqual(actual.cached.map(\.norm), expected.cached.map(\.norm))
            XCTAssertTrue(actual.cached[4].admitted)
            XCTAssertFalse(actual.raw[4].retained)
            XCTAssertEqual(actual.cached[1].admitted, language == "ko")
            XCTAssertTrue(actual.cached[6].admitted)
        }
    }

    func testMergedRecordsRejectInvalidSpansAndNonfiniteScores() throws {
        let scalars = Array("NaCl".unicodeScalars)
        let valid = MergedCandidate(start: 0, end: 4, score: 0.5, tierTwo: false,
                                    noFilter: false, kind: "pool", tier: 1)
        let invalid: [(Range<Int>, Float)] = [
            (-1..<1, 0.5), (0..<0, 0.5), (0..<5, 0.5),
            (0..<1, .nan), (0..<1, .infinity), (0..<1, -.infinity)
        ]
        for (range, score) in invalid {
            let candidate = MergedCandidate(
                start: range.lowerBound, end: range.upperBound, score: score, tierTwo: true,
                noFilter: true, kind: "cleanvar", tier: 3
            )
            for merged in [[candidate, valid], [valid, candidate]] {
                XCTAssertThrowsError(try R117NativeCandidatePool.records(
                    merged: merged, scalars: scalars, language: "ko"
                )) {
                    guard case R117NativeError.invalidPrediction = $0 else {
                        XCTFail("예상하지 못한 오류: \($0)")
                        return
                    }
                }
            }
        }
    }

    func testEmptyMergedRecordsRemainEmpty() throws {
        let result = try R117NativeCandidatePool.records(merged: [], scalars: [], language: "ko")
        XCTAssertTrue(result.raw.isEmpty)
        XCTAssertTrue(result.cached.isEmpty)
    }

    private func mergedCandidate(
        _ term: String, text: String, score: Float, kind: String, tier: Int,
        noFilter: Bool = false
    ) throws -> MergedCandidate {
        let range = try XCTUnwrap(text.range(of: term))
        return MergedCandidate(
            start: text[..<range.lowerBound].unicodeScalars.count,
            end: text[..<range.upperBound].unicodeScalars.count,
            score: score, tierTwo: tier == 2, noFilter: noFilter, kind: kind, tier: tier
        )
    }

    private func legacyRecords(
        merged: [MergedCandidate], scalars: [Unicode.Scalar], language: String
    ) throws -> (raw: [R117NativeRawCandidate], cached: [CachedCandidate]) {
        let raw = try merged.map { candidate in
            guard candidate.start >= 0, candidate.end > candidate.start,
                  candidate.end <= scalars.count, candidate.score.isFinite else {
                throw R117NativeError.invalidPrediction
            }
            let norm = HintNorm.norm(TermHintDecoder.sliceStr(
                scalars, candidate.start, candidate.end
            ))
            let decision = AdmissionDecision.decide(AdmissionInput(
                chars: scalars, language: language, start: candidate.start, end: candidate.end,
                score: candidate.score, noFilter: candidate.noFilter, norm: norm
            ))
            return R117NativeRawCandidate(
                start: candidate.start, end: candidate.end, score: Double(candidate.score),
                kind: candidate.kind, tier: candidate.tier, retained: decision.retained
            )
        }
        let cached = merged.map { candidate in
            let norm = HintNorm.norm(TermHintDecoder.sliceStr(
                scalars, candidate.start, candidate.end
            ))
            let decision = AdmissionDecision.decide(AdmissionInput(
                chars: scalars, language: language, start: candidate.start, end: candidate.end,
                score: candidate.score, noFilter: candidate.noFilter, norm: norm
            ))
            return CachedCandidate(
                start: candidate.start, end: candidate.end, score: Double(candidate.score),
                admitted: decision.admitted, norm: norm
            )
        }
        return (raw, cached)
    }
}
