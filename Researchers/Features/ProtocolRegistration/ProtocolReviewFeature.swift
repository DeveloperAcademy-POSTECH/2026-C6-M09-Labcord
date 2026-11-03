import ComposableArchitecture
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

@Reducer
struct ProtocolReviewFeature {
    @ObservableState
    struct State: Equatable {
        var title: String
        var timerSeconds: [Int]
        var terms: [ProtocolTermCategory: [ProtocolReviewTerm]]
        var expanded: Set<ProtocolTermCategory> = []
        var inputCategory: ProtocolTermCategory?
        var termInput = ""
        var termError: String?
        var attemptedRegistration = false

        var titleValid: Bool {
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 60
        }

        var hasUncommittedTerm: Bool {
            !termInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    enum Action: Equatable {
        case titleChanged(String)
        case expandedChanged(ProtocolTermCategory, Bool)
        case editTerm(ProtocolTermCategory)
        case termChanged(String)
        case addTerm
        case endTermEditing
        case removeTerm(ProtocolTermCategory, UUID)
        case saveTimer(Int?, Int)
        case deleteTimer(Int)
        case registerTapped
        case backTapped
    }

    @Dependency(\.uuid) var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .titleChanged(title):
                state.title = String(title.prefix(60))
            case let .expandedChanged(category, isExpanded):
                if isExpanded {
                    state.expanded.insert(category)
                } else {
                    guard state.inputCategory != category || !state.hasUncommittedTerm else {
                        return .none
                    }
                    state.expanded.remove(category)
                    if state.inputCategory == category { state.inputCategory = nil }
                }
            case let .editTerm(category):
                guard !state.hasUncommittedTerm else { return .none }
                state.inputCategory = category
                state.termInput = ""
                state.termError = nil
            case let .termChanged(input):
                state.termInput = String(input.prefix(22))
                state.termError = nil
            case .addTerm:
                guard let category = state.inputCategory else { return .none }
                let value = state.termInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return .none }
                let key = ProtocolReviewTerm.comparisonKey(value)
                let existing = state.terms.values.joined().contains {
                    ProtocolReviewTerm.comparisonKey($0.value) == key
                }
                guard !existing else {
                    state.termError = "이미 추가된 항목이에요."
                    return .none
                }
                state.terms[category, default: []].append(.init(id: uuid(), value: value))
                state.termInput = ""
                state.termError = nil
            case .endTermEditing:
                guard !state.hasUncommittedTerm else { return .none }
                state.inputCategory = nil
                state.termInput = ""
                state.termError = nil
            case let .removeTerm(category, id):
                state.terms[category]?.removeAll { $0.id == id }
            case let .saveTimer(index, seconds):
                guard seconds > 0, seconds <= 86_399 else { return .none }
                if let index, state.timerSeconds.indices.contains(index) {
                    state.timerSeconds[index] = seconds
                } else if index == nil {
                    state.timerSeconds.append(seconds)
                }
            case let .deleteTimer(index):
                guard state.timerSeconds.indices.contains(index) else { return .none }
                state.timerSeconds.remove(at: index)
            case .registerTapped:
                state.attemptedRegistration = true
            case .backTapped:
                break
            }
            return .none
        }
    }

}
