import Foundation
@testable import LabcordiOS
import XCTest

final class R117DocumentFeaturesTests: XCTestCase {
    func testWeightedContextAndCandidateFeaturesRemainInColumnOrder() throws {
        let document = R117Encoder.Document(
            offsets: [0..<1, 2..<5],
            vectors: [Array(repeating: 1, count: 384), Array(repeating: 3, count: 384)]
        )
        let values = try document.relativeFeatures(text: "A BCD", spans: [0..<1])
        XCTAssertEqual(Array(values[0].prefix(384)), Array(repeating: 1, count: 384))
        XCTAssertEqual(Array(values[0][384..<768]), Array(repeating: 2.5, count: 384))
        XCTAssertEqual(values[0][768], 1, accuracy: 1e-6)
        let purpose = try document.relativeFeatures(
            text: "A BCD", spans: [2..<5], contextTokenLimit: 1
        )
        XCTAssertEqual(Array(purpose[0].prefix(768)), Array(repeating: 3, count: 768))
    }

    func testWhitespaceAndControlDoNotRequireTokenCoverage() throws {
        let document = R117Encoder.Document(
            offsets: [0..<1, 4..<5],
            vectors: [Array(repeating: 1, count: 384), Array(repeating: 1, count: 384)]
        )
        XCTAssertNoThrow(try document.relativeFeatures(text: "A \u{001C}\tB", spans: [0..<5]))
        XCTAssertThrowsError(try document.relativeFeatures(text: "A 🧪 B", spans: [0..<5]))
    }

    func testInvalidSourceRangesAreRejected() throws {
        let document = R117Encoder.Document(
            offsets: [0..<1], vectors: [Array(repeating: 1, count: 384)]
        )
        for range in [-1..<1, 0..<0, 0..<2] {
            XCTAssertThrowsError(try document.relativeFeatures(text: "A", spans: [range]))
        }
    }

    func testOrderedDuplicateAndZeroWidthOffsetsMatchLegacyBits() throws {
        let offsets = [-3..<0, 0..<0, 0..<2, 0..<2, 1..<3, 3..<3, 3..<7, 7..<7, 9..<11]
        try assertPoolingMatchesLegacy(
            offsets: offsets,
            ranges: [-5..<(-3), -3..<0, -1..<1, 0..<1, 0..<2, 1..<3, 2..<4,
                     3..<7, 6..<9, 7..<9, 9..<10, 10..<11, 11..<13, -5..<13, 3..<3]
        )
    }

    func testEitherUnorderedBoundaryFallsBackWithoutReorderingAccumulation() throws {
        for offsets in [
            [0..<8, 2..<4, 4..<9],
            [2..<3, 0..<4, 4..<9],
            [5..<8, 0..<2, 3..<6, 0..<0]
        ] {
            try assertPoolingMatchesLegacy(
                offsets: offsets,
                ranges: [-1..<0, 0..<1, 1..<4, 2..<7, 7..<9, 9..<10, 0..<9, 4..<4]
            )
        }
    }

    func testOrderedPartialOverlapsAndRangesOutsideBothEndsMatchLegacyBits() throws {
        let offsets = (0..<100).map { index in
            let lower = (index / 3) * 2
            return lower..<(lower + index % 3)
        }
        let ranges = (0..<150).map { index in
            let lower = (index * 7) % 80 - 7
            return lower..<(lower + index % 13)
        }
        try assertPoolingMatchesLegacy(offsets: offsets, ranges: ranges)
    }

    func testEmptyAndOnlyZeroWidthOffsetsRemainUncovered() throws {
        for offsets: [Range<Int>] in [[], [0..<0], [0..<0, 1..<1, 1..<1, 3..<3]] {
            try assertPoolingMatchesLegacy(
                offsets: offsets, ranges: [-1..<0, 0..<0, 0..<1, 0..<4, 3..<4]
            )
        }
    }

    func testRelativeFeaturesAndLimitedContextMatchLegacyBits() throws {
        let text = String(repeating: "A", count: 32)
        let offsets = [0..<2, 1..<4, 4..<4, 4..<8, 7..<13, 13..<13, 13..<19, 19..<32]
        let vectors = vectors(count: offsets.count)
        let document = R117Encoder.Document(offsets: offsets, vectors: vectors)
        let spans = [0..<1, 0..<32, 1..<8, 4..<5, 7..<14, 18..<32, 31..<32]
        for limit: Int? in [nil, 1, 3, 7, 8, 20] {
            let contextOffsets = limit.map { Array(offsets.prefix($0)) } ?? offsets
            let contextVectors = limit.map { Array(vectors.prefix($0)) } ?? vectors
            let context = try legacyPooled(
                offsets: contextOffsets, vectors: contextVectors, range: 0..<32
            )
            let expected = try spans.map { range in
                R117Encoder.relative(
                    try legacyPooled(offsets: offsets, vectors: vectors, range: range),
                    context: context
                )
            }
            let actual = try document.relativeFeatures(
                text: text, spans: spans, contextTokenLimit: limit
            )
            XCTAssertEqual(actual.map { $0.map(\.bitPattern) },
                           expected.map { $0.map(\.bitPattern) })
        }
    }

    private func assertPoolingMatchesLegacy(
        offsets: [Range<Int>], ranges: [Range<Int>],
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let vectors = vectors(count: offsets.count)
        let document = R117Encoder.Document(offsets: offsets, vectors: vectors)
        for range in ranges {
            let expected: [Float]
            do {
                expected = try legacyPooled(offsets: offsets, vectors: vectors, range: range)
            } catch R117RuntimeError.uncoveredSource {
                XCTAssertThrowsError(try document.pooled(in: range), file: file, line: line) {
                    guard case R117RuntimeError.uncoveredSource = $0 else {
                        XCTFail("예상하지 못한 오류: \($0)", file: file, line: line)
                        return
                    }
                }
                continue
            }
            let actual = try document.pooled(in: range)
            XCTAssertEqual(actual.map(\.bitPattern), expected.map(\.bitPattern),
                           "범위: \(range)", file: file, line: line)
        }
    }

    private func vectors(count: Int) -> [[Double]] {
        (0..<count).map { row in
            (0..<384).map { column in
                switch (row + column) % 7 {
                case 0: 1e16
                case 1: -1e16
                case 2: Double(Float.leastNonzeroMagnitude)
                default: Double((row + 3) * (column % 19 - 9)) / 7
                }
            }
        }
    }

    private func legacyPooled(
        offsets: [Range<Int>], vectors: [[Double]], range: Range<Int>
    ) throws -> [Float] {
        let overlaps = offsets.enumerated().compactMap { index, offset -> (Int, Int)? in
            let weight = max(0, min(offset.upperBound, range.upperBound)
                - max(offset.lowerBound, range.lowerBound))
            return weight > 0 ? (index, weight) : nil
        }
        let total = overlaps.reduce(0) { $0 + $1.1 }
        guard total > 0 else { throw R117RuntimeError.uncoveredSource }
        var output = Array(repeating: 0.0, count: 384)
        for (index, weight) in overlaps {
            let scale = Double(Float(weight) / Float(total))
            for column in 0..<384 { output[column] += vectors[index][column] * scale }
        }
        return output.map(Float.init)
    }
}
