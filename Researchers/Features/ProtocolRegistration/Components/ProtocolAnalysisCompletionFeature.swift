import ComposableArchitecture

@Reducer
struct ProtocolAnalysisCompletionFeature {
    @ObservableState
    struct State: Equatable {
        var showReviewConfirmation = false
        var showExitConfirmation = false
    }

    enum Action: Equatable {
        case reviewTapped(requiresConfirmation: Bool)
        case backTapped
        case dismissReviewConfirmation
        case dismissExitConfirmation
        case confirmReview
        case confirmExit
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case review
        case exit
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .reviewTapped(requiresConfirmation):
                if requiresConfirmation {
                    state.showReviewConfirmation = true
                } else {
                    return .send(.delegate(.review))
                }
            case .backTapped:
                state.showExitConfirmation = true
            case .dismissReviewConfirmation:
                state.showReviewConfirmation = false
            case .dismissExitConfirmation:
                state.showExitConfirmation = false
            case .confirmReview:
                state.showReviewConfirmation = false
                return .send(.delegate(.review))
            case .confirmExit:
                state.showExitConfirmation = false
                return .send(.delegate(.exit))
            case .delegate:
                break
            }
            return .none
        }
    }
}
