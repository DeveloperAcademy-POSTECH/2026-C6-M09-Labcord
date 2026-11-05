import ComposableArchitecture
import LabcordiOS

@Reducer
struct AppFeature {
    @Reducer
    enum Path {
        case registration(ProtocolRegistrationFeature)
        case session(ExperimentSessionFeature)
        case result(ExperimentResultFeature)
    }

    @ObservableState
    struct State: Equatable {
        @Shared(.appStorage("onboardingHasCompleted")) var hasCompletedOnboarding = false
        var onboarding: OnboardingFeature.State?
        var firstHome: FirstHomeFeature.State?
        var home = HomeFeature.State()
        var path = StackState<Path.State>()
    }

    enum Action {
        case appeared
        case onboarding(OnboardingFeature.Action)
        case firstHome(FirstHomeFeature.Action)
        case home(HomeFeature.Action)
        case path(StackActionOf<Path>)
        case closeRegistration(StackElementID)
        case registrationSucceeded(StackElementID, ExperimentListEntry)
        case showResult(StackElementID)
        case returnHome(StackElementID)
    }

    var body: some Reducer<State, Action> {
        CombineReducers {
            Scope(state: \.home, action: \.home) { HomeFeature() }

            Reduce { _, _ in .none }
                .ifLet(\.onboarding, action: \.onboarding) { OnboardingFeature() }

            Reduce { _, _ in .none }
                .ifLet(\.firstHome, action: \.firstHome) { FirstHomeFeature() }

            Reduce { state, action in
                switch action {
                case .appeared:
                    if !state.hasCompletedOnboarding {
                        state.onboarding = OnboardingFeature.State()
                    }
                    return .none

                case .onboarding(.delegate(.finished)):
                    state.onboarding = nil
                    state.$hasCompletedOnboarding.withLock { $0 = true }
                    state.firstHome = FirstHomeFeature.State()
                    return .none

                case .firstHome(.delegate(.registerTapped)):
                    state.firstHome = nil
                    return .send(.home(.addTapped))

                case .onboarding, .firstHome:
                    return .none

                case .home(.addTapped):
                    guard state.path.isEmpty, !state.home.list.isDeleting,
                          state.home.list.pendingDeletion == nil else { return .none }
                    state.path.append(.registration(ProtocolRegistrationFeature.State()))
                    return .send(.home(.list(.cancelLoad)))

                case let .home(.list(.experimentTapped(identifier))):
                    guard state.path.isEmpty,
                          !state.home.list.isDeleting,
                          let entry = state.home.list.entries.first(where: { $0.id == identifier })
                    else {
                        return .none
                    }
                    if entry.status == .completed {
                        state.path.append(
                            .result(ExperimentResultFeature.State(
                                experimentID: identifier,
                                isOpenedFromHome: true
                            ))
                        )
                    } else {
                        state.path.append(
                            .session(ExperimentSessionFeature.State(experimentID: identifier))
                        )
                    }
                    return .send(.home(.list(.cancelLoad)))

                case let .path(.element(id: id, action: .registration(.backTapped))):
                    return .send(.closeRegistration(id))

                case let .closeRegistration(id):
                    guard state.path[id: id, case: \.registration]?.isSaving == false else {
                        return .none
                    }
                    state.path.pop(from: id)
                    return .none

                case let .path(.element(id: id, action: .registration(.saveSucceeded(entry)))):
                    return .send(.registrationSucceeded(id, entry))

                case let .registrationSucceeded(id, entry):
                    guard state.path.ids.last == id else { return .none }
                    state.path.append(.session(ExperimentSessionFeature.State(experimentID: entry.id)))
                    return .send(.home(.list(.created(entry))))

                case let .path(.element(id: id, action: .session(.stopCompleted))):
                    return .send(.showResult(id))

                case let .path(.element(id: id, action: .session(.homeExitCompleted))):
                    return .send(.returnHome(id))

                case let .showResult(id):
                    guard state.path.ids.last == id,
                          let experimentID = state.path[id: id, case: \.session]?.experimentID else {
                        return .none
                    }
                    state.path.append(
                        .result(ExperimentResultFeature.State(experimentID: experimentID))
                    )
                    return .none

                case let .path(.element(id: id, action: .result(.homeTapped))):
                    return .send(.returnHome(id))

                case let .returnHome(id):
                    guard state.path.ids.last == id else { return .none }
                    state.path.removeAll()
                    return .send(.home(.list(.load)))

                case .home, .path:
                    return .none
                }
            }
            .forEach(\.path, action: \.path)
        }
    }
}

extension AppFeature.Path.State: Equatable {}
