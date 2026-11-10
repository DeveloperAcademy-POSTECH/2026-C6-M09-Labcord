import ComposableArchitecture

extension AppFeature {
    func handleLaunch(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case .appeared:
            if !state.hasCompletedOnboarding {
                state.onboarding = OnboardingFeature.State()
            }

        case .onboarding(.delegate(.finished)):
            state.onboarding = nil
            state.$hasCompletedOnboarding.withLock { $0 = true }

        default:
            break
        }
        return .none
    }
}
