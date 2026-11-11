import ComposableArchitecture
import Foundation
import LabcordiOS

@Reducer
struct ProtocolReviewFeature {
    static let maximumTimerSeconds = Int(Double(Int.max).nextDown)

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
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && title.count <= 60
        }

        var timersValid: Bool {
            timerSeconds.allSatisfy {
                (1...ProtocolReviewFeature.maximumTimerSeconds).contains($0)
            }
        }

        var hasUncommittedTerm: Bool {
            !trimmedTermInput.isEmpty
        }

        var trimmedTermInput: String {
            termInput.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var termCharacterCount: Int {
            trimmedTermInput.filter { !$0.isWhitespace }.count
        }

        var titleError: String? {
            title.count > 60 ? "최대 60자까지 입력할 수 있습니다." : nil
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
                state.title = title
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
                state.termInput = input
                let value = state.trimmedTermInput
                if state.termCharacterCount > 22 {
                    state.termError = "최대 22자까지 입력할 수 있습니다."
                } else if !value.isEmpty, let category = state.inputCategory,
                          state.terms[category, default: []].contains(where: {
                              ProtocolReviewTerm.comparisonKey($0.value)
                                  == ProtocolReviewTerm.comparisonKey(value)
                          }) {
                    state.termError = "이미 추가된 항목이에요."
                } else {
                    state.termError = nil
                }
            case .addTerm:
                guard let category = state.inputCategory else { return .none }
                let value = state.trimmedTermInput
                guard !value.isEmpty else {
                    state.termError = "용어를 입력해 주세요."
                    return .none
                }
                guard state.termCharacterCount <= 22 else {
                    state.termError = "최대 22자까지 입력할 수 있습니다."
                    return .none
                }
                let key = ProtocolReviewTerm.comparisonKey(value)
                let existing = state.terms[category, default: []].contains {
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
                guard (1...Self.maximumTimerSeconds).contains(seconds) else { return .none }
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
