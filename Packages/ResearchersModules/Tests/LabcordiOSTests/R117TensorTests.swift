import CoreML
import Foundation
@testable import LabcordiOS
import XCTest

final class R117TensorTests: XCTestCase {
    func testInputPreservesIDsAndPaddingMask() throws {
        for ids in [[], [7], [0, 42, 99, 2]] {
            let provider = try R117Tensor.input(ids: ids)
            let input = try XCTUnwrap(provider.featureValue(for: "ids")?.multiArrayValue)
            let mask = try XCTUnwrap(provider.featureValue(for: "attention_mask")?.multiArrayValue)
            XCTAssertEqual(input.shape.map(\.intValue), [1, max(2, ids.count)])
            for index in 0..<max(2, ids.count) {
                XCTAssertEqual(input[index].intValue, index < ids.count ? ids[index] : 1)
                XCTAssertEqual(mask[index].intValue, index < ids.count ? 1 : 0)
            }
        }
    }

    func testBufferRowsAndPoolPreserveScalarOrderWithStrides() throws {
        let storage = UnsafeMutablePointer<Float>.allocate(capacity: 3_072)
        storage.initialize(repeating: -999, count: 3_072)
        let output = try MLMultiArray(
            dataPointer: storage, shape: [1, 3, 384], dataType: .float32,
            strides: [3_072, 1_024, 2]
        ) { $0.deallocate() }
        for row in 0..<3 {
            for column in 0..<384 {
                output[[0, NSNumber(value: row), NSNumber(value: column)]] =
                    NSNumber(value: Float(row * 384 + column) / 3)
            }
        }
        let legacy = (0..<3).map { row in
            (0..<384).map { output[row * 384 + $0].floatValue }
        }
        XCTAssertEqual(R117Tensor.rows(output, count: 3), legacy)
        var pooled = Array(repeating: Float(0), count: 384)
        for row in [2, 0, 1] {
            for column in 0..<384 { pooled[column] += legacy[row][column] }
        }
        XCTAssertEqual(R117Tensor.pooled(output, selected: [2, 0, 1]), pooled.map { $0 / 3 })
    }

    func testEmbeddingsRejectsUnexpectedShapeAndType() throws {
        for array in [
            try MLMultiArray(shape: [1, 2, 384], dataType: .double),
            try MLMultiArray(shape: [2, 384], dataType: .float32),
            try MLMultiArray(shape: [1, 3, 384], dataType: .float32)
        ] {
            let provider = try MLDictionaryFeatureProvider(dictionary: ["token_embeddings": array])
            XCTAssertThrowsError(try R117Tensor.embeddings(from: provider, length: 2))
        }
    }

    func testEmbeddingsAcceptsDeclaredFloatShape() throws {
        let array = try MLMultiArray(shape: [1, 2, 384], dataType: .float32)
        let provider = try MLDictionaryFeatureProvider(dictionary: ["token_embeddings": array])
        XCTAssertTrue(try R117Tensor.embeddings(from: provider, length: 1) === array)
    }
}
