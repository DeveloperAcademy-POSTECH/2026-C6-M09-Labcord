import ComposableArchitecture
import Foundation
import LabcordiOS
import SwiftUI

@Reducer
struct ExperimentEntryFeature {
    @ObservableState
    struct State: Equatable {
        var entries: [ExperimentListEntry] = []
        var isRegistering = false
        var isSaving = false
        var isDeleting = false
        var pendingDeletion: ExperimentListEntry?
        var deletionID: UUID?
        var pendingID: UUID?
        var failure: Failure?
        var loadRevision = 0
    }

    nonisolated enum Failure: Error, Equatable, Sendable {
        case loading
        case saving
        case deleting
    }

    nonisolated struct SavedExperiment: Equatable, Sendable {
        let entry: ExperimentListEntry
        let refreshedEntries: Result<[ExperimentListEntry], Failure>
    }

    enum Action: Equatable {
        case load
        case loaded(Int, Result<[ExperimentListEntry], Failure>)
        case addTapped
        case registrationPresented(Bool)
        case skipTapped
        case saved(Result<SavedExperiment, Failure>)
        case retryTapped(Failure)
        case dismissFailure
        case deleteRequested(UUID)
        case deleteCancelled
        case deleteConfirmed(UUID)
        case deleteSucceeded(UUID)
        case deleteFailed(UUID)
        case editTapped(UUID)
        case experimentTapped(UUID)
        case sourceTapped(ProtocolSource)
        case settingsTapped
        case delegate(Delegate)
    }

    nonisolated enum Delegate: Equatable, Sendable {
        case experimentCreated(UUID)
        case experimentSelected(UUID)
        case protocolEditRequested(UUID)
        case protocolSourceRequested(ProtocolSource)
        case settingsRequested
    }

    @Dependency(\.experimentClient) var experimentClient
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now

    private nonisolated enum CancelID {
        case load
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .load:
                guard !state.isSaving, !state.isDeleting else { return .none }
                if state.failure == .loading {
                    state.failure = nil
                }
                state.loadRevision += 1
                let revision = state.loadRevision
                return .run { send in
                    do {
                        let entries = try await experimentClient.load()
                        await send(.loaded(revision, .success(entries)))
                    } catch {
                        await send(.loaded(revision, .failure(.loading)))
                    }
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .loaded(revision, result):
                guard revision == state.loadRevision else { return .none }
                switch result {
                case let .success(entries):
                    state.entries = entries.sorted(by: ExperimentListEntry.newestFirst)
                case .failure:
                    state.failure = .loading
                }
                return .none

            case .addTapped:
                guard !state.isRegistering, !state.isDeleting,
                      state.pendingDeletion == nil else { return .none }
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
                state.loadRevision += 1
                let date = now
                return .concatenate(
                    .cancel(id: CancelID.load),
                    .run { send in
                        do {
                            let entry = try await experimentClient.create(identifier, date)
                            let refreshedEntries: Result<[ExperimentListEntry], Failure>
                            do {
                                refreshedEntries = .success(try await experimentClient.load())
                            } catch {
                                refreshedEntries = .failure(.loading)
                            }
                            await send(.saved(.success(SavedExperiment(
                                entry: entry, refreshedEntries: refreshedEntries
                            ))))
                        } catch {
                            await send(.saved(.failure(.saving)))
                        }
                    }
                )

            case let .saved(result):
                guard state.isSaving else { return .none }
                state.isSaving = false
                switch result {
                case let .success(saved):
                    switch saved.refreshedEntries {
                    case let .success(entries):
                        state.entries = entries
                        state.failure = nil
                    case .failure:
                        state.failure = .loading
                    }
                    state.entries.removeAll { $0.id == saved.entry.id }
                    state.entries.append(saved.entry)
                    state.entries.sort(by: ExperimentListEntry.newestFirst)
                    state.isRegistering = false
                    state.pendingID = nil
                    return .send(.delegate(.experimentCreated(saved.entry.id)))
                case .failure:
                    state.failure = .saving
                    return .none
                }

            case let .retryTapped(failure):
                state.failure = nil
                switch failure {
                case .loading:
                    return .send(.load)
                case .saving:
                    return .send(.skipTapped)
                case .deleting:
                    guard let identifier = state.deletionID else { return .none }
                    return delete(identifier, state: &state)
                }

            case .dismissFailure:
                state.failure = nil
                return .none

            case let .deleteRequested(identifier):
                guard !state.isRegistering, !state.isSaving, !state.isDeleting,
                      state.failure == nil,
                      let entry = state.entries.first(where: { $0.id == identifier }) else {
                    return .none
                }
                state.pendingDeletion = entry
                return .none

            case .deleteCancelled:
                state.pendingDeletion = nil
                return .none

            case let .deleteConfirmed(identifier):
                state.pendingDeletion = nil
                return delete(identifier, state: &state)

            case let .deleteSucceeded(identifier):
                guard state.isDeleting, state.deletionID == identifier else { return .none }
                state.entries.removeAll { $0.id == identifier }
                state.isDeleting = false
                state.deletionID = nil
                return .none

            case let .deleteFailed(identifier):
                guard state.isDeleting, state.deletionID == identifier else { return .none }
                state.isDeleting = false
                state.failure = .deleting
                return .none

            case let .editTapped(identifier):
                guard !state.isDeleting,
                      state.entries.contains(where: { $0.id == identifier }) else { return .none }
                return .send(.delegate(.protocolEditRequested(identifier)))

            case let .experimentTapped(identifier):
                guard !state.isDeleting,
                      state.entries.contains(where: { $0.id == identifier }) else { return .none }
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

    private func delete(_ identifier: UUID, state: inout State) -> Effect<Action> {
        guard !state.isRegistering, !state.isSaving, !state.isDeleting,
              state.entries.contains(where: { $0.id == identifier }) else { return .none }
        state.isDeleting = true
        state.deletionID = identifier
        state.loadRevision += 1
        return .concatenate(
            .cancel(id: CancelID.load),
            .run { send in
                do {
                    try await experimentClient.delete(identifier)
                    await send(.deleteSucceeded(identifier), animation: .easeInOut(duration: 0.25))
                } catch {
                    await send(.deleteFailed(identifier))
                }
            }
        )
    }
}
