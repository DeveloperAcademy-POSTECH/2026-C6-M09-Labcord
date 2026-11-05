import ComposableArchitecture

@Reducer
struct FirstHomeFeature {

    @ObservableState
    struct State: Equatable {
        @Shared(.appStorage("firstHomeHasShownGuide")) var hasShownGuide = false
        var isGuideVisible = false
    }

    enum Action: Equatable {
        case appeared
        case guideDismissed
        case helpTapped
        case registerTapped
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case registerTapped
        case guideTapped
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                guard !state.hasShownGuide else { return .none }
                state.$hasShownGuide.withLock { $0 = true }
                state.isGuideVisible = true
                return .none

            case .guideDismissed:
                state.isGuideVisible = false
                return .none

            case .helpTapped:
                return .send(.delegate(.guideTapped))

            case .registerTapped:
                return .send(.delegate(.registerTapped))

            case .delegate:
                return .none
            }
        }
    }
}
