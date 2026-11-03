import ComposableArchitecture

@Reducer
struct TitleEditOverlayFeature {
    @ObservableState
    struct State: Equatable {
        let originalTitle: String
        var title: String
        var isDiscardConfirmationPresented = false

        init(originalTitle: String) {
            self.originalTitle = originalTitle
            self.title = originalTitle
        }

        var canSave: Bool {
            !title.isEmpty && title != originalTitle
        }
    }

    enum Action: Equatable {
        case titleChanged(String)
        case dismissRequested
        case discardConfirmed
        case discardCancelled
        case saveTapped
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case dismiss
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .titleChanged(title):
                state.title = String(title.prefix(60))
                return .none

            case .dismissRequested:
                guard state.title != state.originalTitle else {
                    return .send(.delegate(.dismiss))
                }
                state.isDiscardConfirmationPresented = true
                return .none

            case .discardConfirmed:
                guard state.isDiscardConfirmationPresented else { return .none }
                state.isDiscardConfirmationPresented = false
                return .send(.delegate(.dismiss))

            case .discardCancelled:
                state.isDiscardConfirmationPresented = false
                return .none

            case .saveTapped, .delegate:
                return .none
            }
        }
    }
}
