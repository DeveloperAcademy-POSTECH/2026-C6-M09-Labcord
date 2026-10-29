import ComposableArchitecture
import Foundation
import LabcordiOS
import SwiftUI

@Reducer
struct ExperimentListFeature {
    @ObservableState
    struct State: Equatable {
        var entries: [ExperimentListEntry] = []
        var isDeleting = false
        var pendingDeletion: ExperimentListEntry?
        var deletionID: UUID?
        var failure: Failure?
        var loadRevision = 0
        var createdEntry: ExperimentListEntry?
    }

    nonisolated enum Failure: Error, Equatable, Sendable {
        case loading
        case deleting
    }

    enum Action: Equatable {
        case load
        case loaded(Int, Result<[ExperimentListEntry], Failure>)
        case cancelLoad
        case created(ExperimentListEntry)
        case retryTapped(Failure)
        case dismissFailure
        case deleteRequested(UUID)
        case deleteCancelled
        case deleteConfirmed(UUID)
        case deleteSucceeded(UUID)
        case deleteFailed(UUID)
        case editTapped(UUID)
        case experimentTapped(UUID)
    }

    @Dependency(\.experimentClient) var experimentClient

    private nonisolated enum CancelID {
        case load
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .load:
                guard !state.isDeleting else { return .none }
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
                    state.entries = entries
                    if let entry = state.createdEntry {
                        state.entries.removeAll { $0.id == entry.id }
                        state.entries.append(entry)
                        state.createdEntry = nil
                    }
                    state.entries.sort(by: ExperimentListEntry.newestFirst)
                case .failure:
                    state.failure = .loading
                }
                return .none

            case .cancelLoad:
                state.loadRevision += 1
                return .cancel(id: CancelID.load)

            case let .created(entry):
                state.failure = nil
                state.loadRevision += 1
                state.createdEntry = entry
                state.entries.removeAll { $0.id == entry.id }
                state.entries.append(entry)
                state.entries.sort(by: ExperimentListEntry.newestFirst)
                return .send(.load)

            case let .retryTapped(failure):
                state.failure = nil
                switch failure {
                case .loading:
                    return .send(.load)
                case .deleting:
                    guard let identifier = state.deletionID else { return .none }
                    return delete(identifier, state: &state)
                }

            case .dismissFailure:
                state.failure = nil
                return .none

            case let .deleteRequested(identifier):
                guard !state.isDeleting,
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
                if state.createdEntry?.id == identifier {
                    state.createdEntry = nil
                }
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
                return .none

            case .experimentTapped:
                return .none
            }
        }
    }

    private func delete(_ identifier: UUID, state: inout State) -> Effect<Action> {
        guard !state.isDeleting,
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
