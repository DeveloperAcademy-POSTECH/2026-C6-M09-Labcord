import ComposableArchitecture

@Reducer
struct HomeFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.appStorage("firstHomeCompleted")) var hasCompletedFirstHome = false
        @Shared(.appStorage("firstHomeHasShownGuide")) var hasShownGuide = false
        var isGuideVisible = false
        var list = ExperimentListFeature.State()

        var isFirstHome: Bool { !hasCompletedFirstHome }
    }

    enum Action {
        case list(ExperimentListFeature.Action)
        case gestureGuideTapped
        case addTapped
        case settingsTapped
        case firstHomeAppeared
        case firstHomeGuideDismissed
        case firstHomeRegisterTapped
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.list, action: \.list) { ExperimentListFeature() }

        Reduce { state, action in
            switch action {
            case .firstHomeAppeared:
                guard state.isFirstHome, !state.hasShownGuide else { return .none }
                state.$hasShownGuide.withLock { $0 = true }
                state.isGuideVisible = true
                return .none

            case .firstHomeGuideDismissed:
                state.isGuideVisible = false
                return .none

            case .firstHomeRegisterTapped:
                guard state.isFirstHome else { return .none }
                state.$hasCompletedFirstHome.withLock { $0 = true }
                state.isGuideVisible = false
                return .send(.addTapped)

            case .gestureGuideTapped:
                state.isGuideVisible = false
                return .none

            case .addTapped, .settingsTapped, .list:
                return .none
            }
        }
    }
}
