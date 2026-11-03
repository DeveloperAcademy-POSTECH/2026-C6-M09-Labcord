import Darwin
import Foundation

/// 좌표는 Python과 동일한 Unicode scalar 기준이며 UTF-16/Character 인덱스가 아닙니다.
nonisolated struct R117CandidateSpan: Equatable, Sendable {
    let surface: String
    let start: Int
    let end: Int
}

nonisolated enum R117ScoringError: Error {
    case invalidFeatures
    case invalidSourceSpan
    case invalidModelOutput
}

nonisolated enum R117ScoringMath {
    struct Frozen9: Decodable {
        let mean: [Double]
        let std: [Double]
        let weights: [Double]
    }

    struct Components {
        let native: [Double]
        let frozen9: [Double]
        let hgb: [Double]
        let window: [Double]
        let scope: [Double]
        let purpose: [Double]
        let last2: [Double]
    }

    static func zscore(_ values: [Double]) throws -> [Double] {
        guard !values.isEmpty, values.allSatisfy(\.isFinite) else {
            throw R117ScoringError.invalidFeatures
        }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            / Double(values.count)
        let std = sqrt(variance)
        let scale = std > 1e-8 ? std : 1
        return values.map { ($0 - mean) / scale }
    }

    static func native(count: Int) throws -> [Double] {
        guard count > 0 else { throw R117ScoringError.invalidFeatures }
        return try zscore((1...count).map { -log1p(Double($0)) })
    }

    static func frozen9(features: [[Double]], modelData: Data) throws -> [Double] {
        let model = try JSONDecoder().decode(Frozen9.self, from: modelData)
        guard [model.mean, model.std, model.weights].allSatisfy({
            $0.count == 9 && $0.allSatisfy(\.isFinite)
        }), model.std.allSatisfy({ $0 != 0 }) else {
            throw R117ScoringError.invalidFeatures
        }
        let raw = try features.map { row -> Double in
            guard row.count == 9, row.allSatisfy(\.isFinite) else {
                throw R117ScoringError.invalidFeatures
            }
            return (0..<9).reduce(0) {
                $0 + ((row[$1] - model.mean[$1]) / model.std[$1]) * model.weights[$1]
            }
        }
        let learned = try zscore(raw)
        let base = try native(count: features.count)
        return zip(base, learned).map { 0.7 * $0 + 0.3 * $1 }
    }

    /// 원본 전체 후보 pool에서 정규화한 teacher/F와 Float32 head 보정을 합칩니다.
    static func combine(_ values: Components, headLogits: [Double]) throws -> [Double] {
        let components = [
            values.native, values.frozen9, values.hgb, values.window,
            values.scope, values.purpose, values.last2, headLogits
        ]
        guard !values.native.isEmpty, components.allSatisfy({
            $0.count == values.native.count && $0.allSatisfy(\.isFinite)
        }) else { throw R117ScoringError.invalidFeatures }
        let learned = try [values.hgb, values.window, values.scope, values.purpose, values.last2]
            .map { try zscore($0) }
        let scores = values.native.indices.map { index in
            let mean = learned.reduce(0) { $0 + $1[index] } / 5
            let teacher = 0.25 * values.frozen9[index] + 0.25 * values.native[index] + 0.5 * mean
            return teacher + 0.1 * Double(tanhf(Float(headLogits[index])))
        }
        guard scores.allSatisfy(\.isFinite) else { throw R117ScoringError.invalidModelOutput }
        return scores
    }
}
