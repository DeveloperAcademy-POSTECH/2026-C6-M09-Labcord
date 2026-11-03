import CoreML
import Foundation

/// Core ML의 stride를 따라 읽고 써서 원소별 NSNumber 변환을 피합니다.
nonisolated enum R117Tensor {
    static func input(ids: [Int]) throws -> MLDictionaryFeatureProvider {
        let length = max(2, ids.count)
        let shape = [NSNumber(value: 1), NSNumber(value: length)]
        let input = try MLMultiArray(shape: shape, dataType: .int32)
        let mask = try MLMultiArray(shape: shape, dataType: .int32)
        input.withUnsafeMutableBufferPointer(ofType: Int32.self) { values, strides in
            for index in 0..<length {
                values[index * strides[1]] = Int32(index < ids.count ? ids[index] : 1)
            }
        }
        mask.withUnsafeMutableBufferPointer(ofType: Int32.self) { values, strides in
            for index in 0..<length {
                values[index * strides[1]] = index < ids.count ? 1 : 0
            }
        }
        return try MLDictionaryFeatureProvider(dictionary: [
            "ids": input, "attention_mask": mask
        ])
    }

    static func embeddings(
        from prediction: MLFeatureProvider, length: Int
    ) throws -> MLMultiArray {
        guard let output = prediction.featureValue(for: "token_embeddings")?.multiArrayValue,
              output.dataType == .float32,
              output.shape.map(\.intValue) == [1, max(2, length), 384] else {
            throw R117RuntimeError.invalidModelOutput
        }
        return output
    }

    static func rows(_ output: MLMultiArray, count: Int) -> [[Float]] {
        output.withUnsafeBufferPointer(ofType: Float.self) { values in
            let strides = output.strides.map(\.intValue)
            return (0..<count).map { row in
                (0..<384).map { column in values[row * strides[1] + column * strides[2]] }
            }
        }
    }

    static func pooled(_ output: MLMultiArray, selected: [Int]) -> [Float] {
        output.withUnsafeBufferPointer(ofType: Float.self) { values in
            let strides = output.strides.map(\.intValue)
            var pooled = Array(repeating: Float(0), count: 384)
            for row in selected {
                for column in 0..<384 {
                    pooled[column] += values[row * strides[1] + column * strides[2]]
                }
            }
            return pooled.map { $0 / Float(selected.count) }
        }
    }
}
