import ComposableArchitecture
import Foundation
import LabcordiOS

@Reducer
struct HomeFeature {
    @ObservableState
    struct State: Equatable {
        var list = ExperimentListFeature.State()
        var registration = ProtocolRegistrationFeature.State()
        var isRegistering = false
    }

    enum Action: Equatable {
        case list(ExperimentListFeature.Action)
        case addTapped
        case settingsTapped
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
        Scope(state: \.list, action: \.list) { ExperimentListFeature() }
        Scope(state: \.registration, action: \.registration) { ProtocolRegistrationFeature() }
        Reduce { state, action in
            switch action {
            case .addTapped:
                guard !state.isRegistering, !state.list.isDeleting,
                      state.list.pendingDeletion == nil else { return .none }
                state.registration = ProtocolRegistrationFeature.State()
                state.isRegistering = true
                return .send(.list(.cancelLoad))

            case let .list(.delegate(.experimentSelected(identifier))):
                return .send(.delegate(.experimentSelected(identifier)))

            case let .list(.delegate(.protocolEditRequested(identifier))):
                return .send(.delegate(.protocolEditRequested(identifier)))

            case .settingsTapped:
                return .send(.delegate(.settingsRequested))

            case let .registration(.delegate(.experimentCreated(entry))):
                return .merge(
                    .send(.list(.created(entry))),
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

            case .list, .registration, .delegate:
                return .none
            }
        }
    }
}
