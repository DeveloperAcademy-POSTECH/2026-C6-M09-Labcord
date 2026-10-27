import ComposableArchitecture
import Foundation

@Reducer
struct ExperimentEntryFeature {
    @ObservableState
    struct State: Equatable {
        var entries: [ExperimentListEntry] = []
        var isRegistering = false
        var isLoading = false
        var isSaving = false
        var pendingID: UUID?
        var failure: Failure?
        var loadRevision = 0
    }

    nonisolated enum Failure: Error, Equatable, Sendable {
        case loading
        case saving
    }

    enum Action: Equatable {
        case load
        case loaded(Int, Result<[ExperimentListEntry], Failure>)
        case addTapped
        case registrationPresented(Bool)
        case skipTapped
        case saved(Result<ExperimentListEntry, Failure>)
        case retryTapped(Failure)
        case dismissFailure
        case experimentTapped(UUID)
        case sourceTapped(ProtocolSource)
        case settingsTapped
        case delegate(Delegate)

    }

    nonisolated enum Delegate: Equatable, Sendable {
        case experimentCreated(UUID)
        case experimentSelected(UUID)
        case protocolSourceRequested(ProtocolSource)
        case settingsRequested
    }

    @Dependency(\.experimentEntryClient) var client
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now

    private nonisolated enum CancelID {
        case load
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .load:
                guard !state.isSaving else { return .none }
                if state.failure == .loading { state.failure = nil }
                state.isLoading = true
                state.loadRevision += 1
                let revision = state.loadRevision
                return .run { send in
                    do {
                        let entries = try await client.load()
                        await send(.loaded(revision, .success(entries)))
                    } catch {
                        await send(.loaded(revision, .failure(.loading)))
                    }
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .loaded(revision, result):
                guard revision == state.loadRevision else { return .none }
                state.isLoading = false
                switch result {
                case let .success(entries):
                    state.entries = entries.sorted(by: ExperimentListEntry.newestFirst)
                case .failure:
                    state.failure = .loading
                }
                return .none

            case .addTapped:
                guard !state.isRegistering else { return .none }
                state.isRegistering = true
                state.pendingID = nil
                return .none

            case let .registrationPresented(isPresented):
                guard !state.isSaving else { return .none }
                state.isRegistering = isPresented
                if !isPresented {
                    state.pendingID = nil
                    state.failure = nil
                }
                return .none

            case .skipTapped:
                guard state.isRegistering, !state.isSaving, state.failure == nil else {
                    return .none
                }
                let identifier = state.pendingID ?? uuid()
                state.pendingID = identifier
                state.isSaving = true
                state.isLoading = false
                state.loadRevision += 1
                let date = now
                return .concatenate(
                    .cancel(id: CancelID.load),
                    .run { send in
                        do {
                            let entry = try await client.create(identifier, date)
                            await send(.saved(.success(entry)))
                        } catch {
                            await send(.saved(.failure(.saving)))
                        }
                    }
                )

            case let .saved(result):
                guard state.isSaving else { return .none }
                state.isSaving = false
                switch result {
                case let .success(entry):
                    state.entries.removeAll { $0.id == entry.id }
                    state.entries.append(entry)
                    state.entries.sort(by: ExperimentListEntry.newestFirst)
                    state.isRegistering = false
                    state.pendingID = nil
                    return .concatenate(
                        .send(.delegate(.experimentCreated(entry.id))),
                        .send(.load)
                    )
                case .failure:
                    state.failure = .saving
                    return .none
                }

            case let .retryTapped(failure):
                state.failure = nil
                switch failure {
                case .loading: return .send(.load)
                case .saving: return .send(.skipTapped)
                }

            case .dismissFailure:
                state.failure = nil
                return .none

            case let .experimentTapped(identifier):
                guard state.entries.contains(where: { $0.id == identifier }) else { return .none }
                return .send(.delegate(.experimentSelected(identifier)))

            case let .sourceTapped(source):
                guard state.isRegistering, !state.isSaving else { return .none }
                return .send(.delegate(.protocolSourceRequested(source)))

            case .settingsTapped:
                return .send(.delegate(.settingsRequested))

            case .delegate:
                return .none
            }
        }
    }
}
