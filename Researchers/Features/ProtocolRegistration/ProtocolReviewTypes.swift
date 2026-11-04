import Foundation
import LabcordiOS

nonisolated enum ProtocolTermCategory: Int, CaseIterable, Equatable, Hashable, Sendable {
    case materials, samples, glossary, units

    var title: String {
        switch self {
        case .materials: "시약·재료"
        case .samples: "샘플·분석 대상"
        case .glossary: "실험 용어"
        case .units: "단위"
        }
    }
}

nonisolated struct ProtocolReviewTerm: Identifiable, Equatable, Sendable {
    let id: UUID
    var value: String

    static func comparisonKey(_ value: String) -> String {
        ProtocolTermNormalizer.key(value)
    }
}
