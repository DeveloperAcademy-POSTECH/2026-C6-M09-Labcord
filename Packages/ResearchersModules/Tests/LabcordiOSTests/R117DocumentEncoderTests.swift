import Foundation
@testable import LabcordiOS
import XCTest

final class R117DocumentEncoderTests: XCTestCase {
    func testTwoWindowsAverageTheSameOverlapAfterReverseCompletion() async throws {
        let encoding = encoding(count: 600)
        let predictor = DocumentWindowPredictor()
        let result = try await R117DocumentEncoder.document(encoding: encoding) { ids in
            try await predictor.predict(ids)
        }
        XCTAssertEqual(result.offsets, encoding.offsets)
        XCTAssertEqual(result.vectors.count, 600)
        for index in 0..<600 {
            let expected: Double = index < 448 ? 1 : (index < 512 ? 2 : 3)
            XCTAssertEqual(result.vectors[index], Array(repeating: expected, count: 384))
        }
        let metrics = await predictor.metrics()
        XCTAssertEqual(metrics.calls.sorted { $0.start < $1.start }, [
            DocumentWindowCall(start: 0, count: 512),
            DocumentWindowCall(start: 448, count: 152)
        ])
        XCTAssertEqual(metrics.finished, [448, 0])
        XCTAssertEqual(metrics.peak, 2)
    }

    func testFixedBatchesNeverStartAThirdWindowBeforeBothPredecessorsFinish() async throws {
        let encoding = encoding(count: 1_900)
        let predictor = DocumentWindowPredictor()
        let result = try await R117DocumentEncoder.document(encoding: encoding) { ids in
            try await predictor.predict(ids)
        }
        let metrics = await predictor.metrics()
        XCTAssertEqual(metrics.peak, 2)
        XCTAssertFalse(metrics.startedNextBatchEarly)
        XCTAssertEqual(metrics.calls.map(\.start).sorted(), [0, 448, 896, 1_344, 1_792])
        XCTAssertEqual(result.offsets, encoding.offsets)
        for index in 0..<1_900 {
            let values = stride(from: 0, to: 1_900, by: 448).compactMap { start -> Float? in
                guard (start..<min(start + 512, 1_900)).contains(index) else { return nil }
                return Float(2 * (start / 448) + 1)
            }
            let sum = values.reduce(Float(0), +)
            XCTAssertEqual(result.vectors[index],
                           Array(repeating: Double(sum) / Double(values.count), count: 384))
        }
    }

    func testFloat32AdditionPrecedesDoubleAveragingWithoutRoundingAwaySubnormals() async throws {
        let large: Float = 16_777_216
        let small: Float = 1
        let first = try await R117DocumentEncoder.document(encoding: encoding(count: 600)) { ids in
            let value = ids.first == 10_000 ? large : small
            return Array(repeating: Array(repeating: value, count: 384), count: ids.count)
        }
        XCTAssertEqual(first.vectors[448][0], Double(large + small) / 2)
        XCTAssertNotEqual(first.vectors[448][0], (Double(large) + Double(small)) / 2)

        let least = Float.leastNonzeroMagnitude
        let second = try await R117DocumentEncoder.document(
            encoding: encoding(count: 600)
        ) { ids in
            let value: Float = ids.first == 10_000 ? least : 0
            return Array(repeating: Array(repeating: value, count: 384), count: ids.count)
        }
        XCTAssertEqual(second.vectors[448][0], Double(least) / 2)
        XCTAssertGreaterThan(second.vectors[448][0], 0)
        XCTAssertNotEqual(second.vectors[448][0], Double(least / 2))
    }

    func testBoundaryWindowsKeepTheOriginalStrideAndNeverAddSpecialTokens() async throws {
        for count in [1, 448, 449, 512, 513, 897] {
            let recorder = DocumentWindowRecorder()
            let result = try await R117DocumentEncoder.document(encoding: encoding(count: count)) {
                await recorder.record($0)
            }
            let actual = await recorder.calls().sorted { $0.start < $1.start }
            let expected = stride(from: 0, to: count, by: 448).map {
                DocumentWindowCall(start: $0, count: min(512, count - $0))
            }
            XCTAssertEqual(actual, expected)
            XCTAssertEqual(result.vectors.count, count)
            XCTAssertTrue(result.vectors.allSatisfy { $0 == Array(repeating: 1, count: 384) })
        }
    }

    func testEmptyAndMisalignedEncodingsAreRejectedBeforePrediction() async {
        do {
            _ = try await R117DocumentEncoder.document(encoding: encoding(count: 0)) { _ in
                throw DocumentPredictionFailure.unexpectedPrediction
            }
            XCTFail("빈 인코딩을 허용함")
        } catch R117RuntimeError.uncoveredSource {
            // 토큰이 없는 문서는 추론하지 않습니다.
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }
        for input in [
            R117Tokenizer.Encoding(ids: [10_000], offsets: []),
            R117Tokenizer.Encoding(ids: [], offsets: [0..<1])
        ] {
            do {
                _ = try await R117DocumentEncoder.document(encoding: input) { _ in
                    throw DocumentPredictionFailure.unexpectedPrediction
                }
                XCTFail("토큰과 좌표 수의 불일치를 허용함")
            } catch R117RuntimeError.invalidTokenizer {
                // 잘못된 인코딩은 모델에 전달하지 않습니다.
            } catch {
                XCTFail("예상하지 못한 오류: \(error)")
            }
        }
    }

    func testInvalidPredictionShapeIsRejectedBeforeMerging() async {
        for rows in [[], [[Float](repeating: 0, count: 383)],
                     Array(repeating: [Float](repeating: 0, count: 384), count: 2)] {
            do {
                _ = try await R117DocumentEncoder.document(
                    encoding: encoding(count: 1)
                ) { _ in rows }
                XCTFail("잘못된 모델 출력 크기를 허용함")
            } catch R117RuntimeError.invalidModelOutput {
                // 누산 배열에 접근하기 전에 행·차원 수를 검증합니다.
            } catch {
                XCTFail("예상하지 못한 오류: \(error)")
            }
        }
    }

    func testCancellationDrainsBothPredictionsWithoutSubmittingAnotherBatch() async throws {
        let input = encoding(count: 1_900)
        let gate = DocumentCancellationGate()
        let task = Task {
            try await R117DocumentEncoder.document(encoding: input) { ids in
                try await gate.predict(ids)
            }
        }
        await gate.waitForTwoPredictions()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("취소한 작업이 문서 특징을 반환함")
        } catch is CancellationError {
            let metrics = await gate.metrics()
            XCTAssertEqual(metrics.started, 2)
            XCTAssertEqual(metrics.active, 0)
        }
    }

    func testAlreadyCancelledTaskDoesNotStartPrediction() async {
        let input = encoding(count: 600)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await R117DocumentEncoder.document(encoding: input) { _ in
                throw DocumentPredictionFailure.unexpectedPrediction
            }
        }
        do {
            _ = try await task.value
            XCTFail("이미 취소된 작업이 문서 특징을 반환함")
        } catch is CancellationError {
            // 시작 전 취소 시 predictor를 호출하지 않습니다.
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }
    }

    private func encoding(count: Int) -> R117Tokenizer.Encoding {
        R117Tokenizer.Encoding(
            ids: (0..<count).map { 10_000 + $0 },
            offsets: (0..<count).map { (2 * $0)..<(2 * $0 + 1) }
        )
    }
}

private struct DocumentWindowCall: Equatable, Sendable {
    let start: Int
    let count: Int
}

private enum DocumentPredictionFailure: Error {
    case unexpectedPrediction
}

private actor DocumentWindowPredictor {
    struct Metrics: Sendable {
        let calls: [DocumentWindowCall]
        let finished: [Int]
        let peak: Int
        let startedNextBatchEarly: Bool
    }

    private var calls: [DocumentWindowCall] = []
    private var finished: [Int] = []
    private var active = 0
    private var peak = 0
    private var startedNextBatchEarly = false
    private var firstStarted = false
    private var secondFinished = false
    private var firstWaiter: CheckedContinuation<Void, Never>?
    private var secondWaiter: CheckedContinuation<Void, Never>?

    func predict(_ ids: [Int]) async throws -> [[Float]] {
        let start = try XCTUnwrap(ids.first) - 10_000
        calls.append(DocumentWindowCall(start: start, count: ids.count))
        active += 1
        peak = max(peak, active)
        defer { active -= 1 }
        let previous = stride(from: 0, to: (start / 896) * 896, by: 448)
        if !previous.allSatisfy({ finished.contains($0) }) { startedNextBatchEarly = true }
        if start == 0 {
            firstStarted = true
            firstWaiter?.resume()
            firstWaiter = nil
            if !secondFinished { await withCheckedContinuation { secondWaiter = $0 } }
        } else if start == 448 {
            if !firstStarted { await withCheckedContinuation { firstWaiter = $0 } }
            secondFinished = true
            secondWaiter?.resume()
            secondWaiter = nil
        } else {
            await Task.yield()
        }
        finished.append(start)
        let value = Float(2 * (start / 448) + 1)
        return Array(repeating: Array(repeating: value, count: 384), count: ids.count)
    }

    func metrics() -> Metrics {
        Metrics(calls: calls, finished: finished, peak: peak,
                startedNextBatchEarly: startedNextBatchEarly)
    }
}

private actor DocumentWindowRecorder {
    private var inputs: [DocumentWindowCall] = []

    func record(_ ids: [Int]) -> [[Float]] {
        inputs.append(DocumentWindowCall(start: (ids.first ?? 0) - 10_000, count: ids.count))
        return Array(repeating: Array(repeating: 1, count: 384), count: ids.count)
    }

    func calls() -> [DocumentWindowCall] { inputs }
}

private actor DocumentCancellationGate {
    private var started = 0
    private var active = 0
    private var waiter: CheckedContinuation<Void, Never>?

    func predict(_ ids: [Int]) async throws -> [[Float]] {
        started += 1
        active += 1
        defer { active -= 1 }
        if started == 2 {
            waiter?.resume()
            waiter = nil
        }
        try await Task.sleep(for: .seconds(30))
        return Array(repeating: Array(repeating: 0, count: 384), count: ids.count)
    }

    func waitForTwoPredictions() async {
        if started < 2 { await withCheckedContinuation { waiter = $0 } }
    }

    func metrics() -> (started: Int, active: Int) { (started, active) }
}
