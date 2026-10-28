import ComposableArchitecture
import Foundation

@Reducer
struct ExperimentEntryFeature {
    @ObservableState
    struct State: Equatable {
        var home = HomeFeature.State()
        var registration = ProtocolRegistrationFeature.State()
        var isRegistering = false
    }

    enum Action: Equatable {
        case home(HomeFeature.Action)
        case registration(ProtocolRegistrationFeature.Action)
        case registrationPresented(Bool)
        case delegate(Delegate)
    }

    nonisolated enum Delegate: Equatable, Sendable {
        case experimentCreated(UUID)
        case experimentSelected(UUID)
        case protocolEditRequested(UUID)
        case protocolSourceRequested(ProtocolSource)
        case settingsRequested
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.home, action: \.home) { HomeFeature() }
        Scope(state: \.registration, action: \.registration) { ProtocolRegistrationFeature() }
        Reduce { state, action in
            switch action {
            case .home(.delegate(.registrationRequested)):
                guard !state.isRegistering else { return .none }
                state.registration = ProtocolRegistrationFeature.State()
                state.isRegistering = true
                return .send(.home(.cancelLoad))

            case let .home(.delegate(.experimentSelected(identifier))):
                return .send(.delegate(.experimentSelected(identifier)))

            case let .home(.delegate(.protocolEditRequested(identifier))):
                return .send(.delegate(.protocolEditRequested(identifier)))

            case .home(.delegate(.settingsRequested)):
                return .send(.delegate(.settingsRequested))

            case let .registration(.delegate(.experimentCreated(entry))):
                state.isRegistering = false
                return .merge(
                    .send(.home(.created(entry))),
                    .send(.delegate(.experimentCreated(entry.id)))
                )

            case .registration(.delegate(.backRequested)):
                state.isRegistering = false
                return .none

            case let .registration(.delegate(.protocolSourceRequested(source))):
                return .send(.delegate(.protocolSourceRequested(source)))

            case let .registrationPresented(isPresented):
                guard !state.registration.isSaving else { return .none }
                state.isRegistering = isPresented
                return .none

            case .home, .registration, .delegate:
                return .none
            }
        }
    }
}
