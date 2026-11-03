import Foundation
@testable import LabcordiOS
import XCTest

final class R117SharedContextEncoderTests: XCTestCase {
    func testOverlapUses510BodyTokensAndIgnoresSpecialTokensAfterReverseCompletion() async throws {
        let predictor = SharedWindowPredictor()
        let rows = try await R117SharedContextEncoder.last2(
            encoding: encoding(600), source: source(600),
            spans: [447..<448, 448..<449, 509..<510, 510..<511, 599..<600]
        ) { await predictor.predict($0) }
        XCTAssertEqual(rows.map { $0[0] }, [1, 2, 2, 3, 3])
        XCTAssertTrue(rows.allSatisfy { Set($0).count == 1 })
        let metrics = await predictor.metrics()
        XCTAssertEqual(metrics.finished, [448, 0])
        XCTAssertEqual(metrics.calls.sorted { $0.start < $1.start }, [
            SharedWindowCall(start: 0, count: 512), SharedWindowCall(start: 448, count: 154)
        ])
        XCTAssertEqual(metrics.peak, 2)
        XCTAssertTrue(metrics.specialTokensCorrect)
    }

    func testCandidateTokensHaveEqualWeightsAndKeepOriginalCandidateOrder() async throws {
        let encoding = R117Tokenizer.Encoding(ids: [10_000, 10_001], offsets: [0..<5, 5..<6])
        let rows = try await R117SharedContextEncoder.last2(
            encoding: encoding, source: source(6), spans: [5..<6, 0..<6, 0..<1, 0..<6]
        ) { ids in
            XCTAssertEqual(ids, [0, 10_000, 10_001, 2])
            return [100, 3, 7, 200].map { Array(repeating: Float($0), count: 384) }
        }
        XCTAssertEqual(rows.map { $0[0] }, [7, 5, 3, 5])
    }

    func testOverlapIsAveragedInFloat32BeforeCandidatePooling() async throws {
        let least = Float.leastNonzeroMagnitude
        let rows = try await R117SharedContextEncoder.last2(
            encoding: encoding(600), source: source(600), spans: [448..<450]
        ) { ids in
            var result = Array(repeating: Array(repeating: Float(0), count: 384), count: ids.count)
            if ids[1] == 10_000 {
                result[449] = Array(repeating: least, count: 384)
                result[450] = Array(repeating: 5 * least, count: 384)
            }
            return result
        }
        XCTAssertEqual(rows[0], Array(repeating: least, count: 384))
        XCTAssertNotEqual(rows[0][0], Float((Double(least) / 2 + Double(5 * least) / 2) / 2))
    }

    func testBoundaryWindowsAndFixedBatchesPreserveTheirInputs() async throws {
        for count in [1, 448, 449, 510, 511, 896, 897, 1_900] {
            let predictor = SharedWindowPredictor()
            let rows = try await R117SharedContextEncoder.last2(
                encoding: encoding(count), source: source(count), spans: [0..<count]
            ) { await predictor.predict($0) }
            let metrics = await predictor.metrics()
            let expected = stride(from: 0, to: count, by: 448).map {
                SharedWindowCall(start: $0, count: min(510, count - $0) + 2)
            }
            XCTAssertEqual(metrics.calls.sorted { $0.start < $1.start }, expected)
            XCTAssertLessThanOrEqual(metrics.peak, 2)
            XCTAssertFalse(metrics.startedNextBatchEarly)
            XCTAssertTrue(metrics.specialTokensCorrect)
            XCTAssertEqual(rows.count, 1)
        }
    }

    func testUnsortedDuplicateOffsetsAndWhitespaceCoverageKeepPrototypeSelection() async throws {
        let encoding = R117Tokenizer.Encoding(
            ids: [10_000, 10_001, 10_002], offsets: [3..<4, 0..<1, 3..<4]
        )
        let rows = try await R117SharedContextEncoder.last2(
            encoding: encoding, source: Array("a \u{7}b".unicodeScalars), spans: [0..<4, 3..<4]
        ) { _ in
            [100, 2, 8, 4, 200].map { Array(repeating: Float($0), count: 384) }
        }
        XCTAssertEqual(rows.map { $0[0] }, [Float(14) / 3, 3])
    }

    func testInvalidEncodingCandidatesAndMissingCoverageDoNotStartPrediction() async {
        let inputs = [
            (R117Tokenizer.Encoding(ids: [1], offsets: []), 0..<1),
            (R117Tokenizer.Encoding(ids: [], offsets: []), 0..<1),
            (R117Tokenizer.Encoding(ids: [1], offsets: [-1..<1]), 0..<1),
            (R117Tokenizer.Encoding(ids: [1], offsets: [0..<3]), 0..<1),
            (encoding(2), -1..<1), (encoding(2), 0..<0), (encoding(2), 0..<3),
            (R117Tokenizer.Encoding(ids: [1], offsets: [0..<1]), 1..<2)
        ]
        for (encoding, span) in inputs {
            do {
                _ = try await R117SharedContextEncoder.last2(
                    encoding: encoding, source: source(2), spans: [span]
                ) { _ in
                    XCTFail("잘못된 입력이 추론을 시작함")
                    return []
                }
                XCTFail("잘못된 좌표 또는 미포함 문자를 허용함")
            } catch { }
        }
    }

    func testInvalidOrNonfinitePredictionIsRejected() async {
        for rows: [[Float]] in [[], [[Float](repeating: 0, count: 384)],
                               Array(repeating: Array(repeating: 0, count: 383), count: 3),
                               Array(repeating: Array(repeating: .nan, count: 384), count: 3)] {
            do {
                _ = try await R117SharedContextEncoder.last2(
                    encoding: encoding(1), source: source(1), spans: [0..<1]
                ) { _ in rows }
                XCTFail("잘못된 출력 또는 NaN을 허용함")
            } catch R117RuntimeError.invalidModelOutput { } catch {
                XCTFail("예상하지 못한 오류: \(error)")
            }
        }
    }

    func testCancellationDrainsBothPredictionsAndDoesNotReportUnpooledCandidates() async throws {
        let gate = SharedPredictionGate()
        let task = Task {
            try await R117SharedContextEncoder.last2(
                encoding: encoding(1_900), source: source(1_900), spans: [0..<1],
                progress: { _, _ in XCTFail("문서 추론 전에 후보 완료를 보고함") },
                prediction: { try await gate.predict($0) }
            )
        }
        await gate.waitForTwo()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("취소된 특징이 반환됨")
        } catch is CancellationError {
            let counts = await gate.counts()
            XCTAssertEqual(counts.started, 2)
            XCTAssertEqual(counts.active, 0)
        }
    }

    func testProgressReportsActuallyPooledCandidatesInOrder() async throws {
        let (events, continuation) = AsyncStream<(Int, Int)>.makeStream()
        let rows = try await R117SharedContextEncoder.last2(
            encoding: encoding(1), source: source(1),
            spans: Array(repeating: 0..<1, count: 45),
            progress: { continuation.yield(($0, $1)) },
            prediction: { ids in
                Array(repeating: Array(repeating: 1, count: 384), count: ids.count)
            }
        )
        continuation.finish()
        var actual: [[Int]] = []
        for await (done, total) in events { actual.append([done, total]) }
        XCTAssertEqual(rows.count, 45)
        XCTAssertEqual(actual, [[20, 45], [40, 45], [45, 45]])
    }

    func testAlreadyCancelledTaskDoesNotStartPrediction() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await R117SharedContextEncoder.last2(
                encoding: encoding(1), source: source(1), spans: [0..<1]
            ) { _ in
                XCTFail("이미 취소된 추론이 시작됨")
                return []
            }
        }
        do {
            _ = try await task.value
            XCTFail("취소된 특징이 반환됨")
        } catch is CancellationError { } catch { XCTFail("예상하지 못한 오류: \(error)") }
    }

    private func encoding(_ count: Int) -> R117Tokenizer.Encoding {
        R117Tokenizer.Encoding(ids: (0..<count).map { 10_000 + $0 },
                               offsets: (0..<count).map { $0..<($0 + 1) })
    }

    private func source(_ count: Int) -> [Unicode.Scalar] {
        Array(repeating: "a", count: count)
    }
}

private struct SharedWindowCall: Equatable, Sendable {
    let start: Int
    let count: Int
}

private actor SharedWindowPredictor {
    struct Metrics: Sendable {
        let calls: [SharedWindowCall]
        let finished: [Int]
        let peak: Int
        let specialTokensCorrect: Bool
        let startedNextBatchEarly: Bool
    }
    private var calls: [SharedWindowCall] = []
    private var finished: [Int] = []
    private var active = 0
    private var peak = 0
    private var specialTokensCorrect = true
    private var startedNextBatchEarly = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var firstWindowStarted = false
    private var firstWindowWaiter: CheckedContinuation<Void, Never>?

    func predict(_ ids: [Int]) async -> [[Float]] {
        let start = ids[1] - 10_000
        calls.append(SharedWindowCall(start: start, count: ids.count))
        active += 1
        peak = max(peak, active)
        specialTokensCorrect = specialTokensCorrect && ids.first == 0 && ids.last == 2
        for previous in stride(from: 0, to: (start / 896) * 896, by: 448)
            where !finished.contains(previous) {
            startedNextBatchEarly = true
        }
        if start == 0 {
            firstWindowStarted = true
            firstWindowWaiter?.resume()
            firstWindowWaiter = nil
            if ids.count > 450, !finished.contains(448) {
                await withCheckedContinuation { waiter = $0 }
            }
        } else if start == 448 {
            if !firstWindowStarted {
                await withCheckedContinuation { firstWindowWaiter = $0 }
            }
            waiter?.resume()
            waiter = nil
        }
        finished.append(start)
        active -= 1
        let value = Float(2 * (start / 448) + 1)
        return [Array(repeating: Float(10_000), count: 384)]
            + Array(repeating: Array(repeating: value, count: 384), count: ids.count - 2)
            + [Array(repeating: Float(20_000), count: 384)]
    }

    func metrics() -> Metrics {
        Metrics(calls: calls, finished: finished, peak: peak,
                specialTokensCorrect: specialTokensCorrect,
                startedNextBatchEarly: startedNextBatchEarly)
    }
}

private actor SharedPredictionGate {
    private var started = 0
    private var active = 0
    private var waiter: CheckedContinuation<Void, Never>?

    func predict(_ ids: [Int]) async throws -> [[Float]] {
        started += 1
        active += 1
        defer { active -= 1 }
        if started == 2 { waiter?.resume(); waiter = nil }
        try await Task.sleep(for: .seconds(30))
        return Array(repeating: Array(repeating: 0, count: 384), count: ids.count)
    }

    func waitForTwo() async {
        if started < 2 { await withCheckedContinuation { waiter = $0 } }
    }

    func counts() -> (started: Int, active: Int) { (started, active) }
}
