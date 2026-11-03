import CoreML
import Foundation

/// 한 번 컴파일한 패키지를 공유하며, 원본 평가처럼 CPU에서 호출합니다.
/// 호출자는 모델 캐시 접근을 한 actor에서 직렬화하고 화면 상태와 수명을 분리해야 합니다.
nonisolated final class R117HeadRunner {
    private let compiledPackageURL: URL
    private let hgb: MLModel
    private var models: [String: MLModel] = [:]
    private var last2Models: [MLModel]?

    init(resourceDirectory: URL) throws {
        let package = resourceDirectory.appendingPathComponent("R117WithTeacherModels.mlpackage")
        compiledPackageURL = try MLModel.compileModel(at: package)
        let hgbURL = resourceDirectory.appendingPathComponent("HGBTeacher.mlmodel")
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        hgb = try MLModel(
            contentsOf: MLModel.compileModel(at: hgbURL), configuration: configuration
        )
        let constraint = hgb.modelDescription.inputDescriptionsByName["handcrafted_features"]?
            .multiArrayConstraint
        guard constraint?.shape.map(\.intValue) == [32], constraint?.dataType == .double else {
            throw R117ScoringError.invalidFeatures
        }
    }

    func predictHead(
        function: String, features: [[Float]], inputName: String = "features"
    ) throws -> [Double] {
        let width = inputName == "pooled_features" ? 384 : 769
        guard !features.isEmpty, features.allSatisfy({
            $0.count == width && $0.allSatisfy(\.isFinite)
        }) else { throw R117ScoringError.invalidFeatures }
        let model = try model(function: function)
        var result: [Double] = []
        result.reserveCapacity(features.count)
        for begin in stride(from: 0, to: features.count, by: 8_192) {
            try Task.checkCancellation()
            let rows = Array(features[begin..<min(begin + 8_192, features.count)])
            let array = try MLMultiArray(
                shape: [NSNumber(value: rows.count), NSNumber(value: width)], dataType: .float32
            )
            array.withUnsafeMutableBufferPointer(ofType: Float.self) { values, strides in
                for (rowIndex, row) in rows.enumerated() {
                    for (column, value) in row.enumerated() {
                        values[rowIndex * strides[0] + column * strides[1]] = value
                    }
                }
            }
            let input = try MLDictionaryFeatureProvider(dictionary: [inputName: array])
            let output = try model.prediction(from: input)
            guard let logits = output.featureValue(for: "logits")?.multiArrayValue,
                  logits.shape.map(\.intValue) == [rows.count, 1],
                  logits.dataType == .float32 else {
                throw R117ScoringError.invalidModelOutput
            }
            result += logits.withUnsafeBufferPointer(ofType: Float.self) { values in
                let stride = logits.strides[0].intValue
                return (0..<rows.count).map { Double(values[$0 * stride]) }
            }
        }
        guard result.allSatisfy(\.isFinite) else { throw R117ScoringError.invalidModelOutput }
        return result
    }

    func predictHGB(features: [[Double]]) throws -> [Double] {
        guard !features.isEmpty, features.allSatisfy({
            $0.count == 32 && $0.allSatisfy(\.isFinite)
        }), hgb.modelDescription.outputDescriptionsByName.count == 1,
              let outputName = hgb.modelDescription.outputDescriptionsByName.keys.first else {
            throw R117ScoringError.invalidFeatures
        }
        return try features.map { row in
            try Task.checkCancellation()
            let array = try MLMultiArray(shape: [32], dataType: .double)
            for (index, value) in row.enumerated() { array[index] = NSNumber(value: value) }
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "handcrafted_features": array
            ])
            let output = try hgb.prediction(from: input)
            guard let value = output.featureValue(for: outputName), value.type == .double,
                  value.doubleValue.isFinite else { throw R117ScoringError.invalidModelOutput }
            return value.doubleValue
        }
    }

    func model(function: String) throws -> MLModel {
        if let cached = models[function] { return cached }
        let loaded = try load(function: function)
        models[function] = loaded
        return loaded
    }

    func last2ModelPool(maximumModels: Int = 4) throws -> [MLModel] {
        try Task.checkCancellation()
        let count = min(max(1, maximumModels), Self.encoderModelCount(
            processors: ProcessInfo.processInfo.activeProcessorCount
        ))
        var pool: [MLModel]
        if let cached = last2Models {
            pool = cached
        } else {
            pool = [try model(function: "teacher_last2")]
        }
        while pool.count < count {
            try Task.checkCancellation()
            pool.append(try load(function: "teacher_last2"))
        }
        try Task.checkCancellation()
        last2Models = pool
        return Array(pool.prefix(count))
    }

    static func encoderModelCount(processors: Int) -> Int {
        min(4, max(1, processors / 2))
    }

    private func load(function: String) throws -> MLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        configuration.functionName = function
        return try MLModel(contentsOf: compiledPackageURL, configuration: configuration)
    }
}
