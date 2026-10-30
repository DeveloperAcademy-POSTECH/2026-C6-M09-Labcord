import ComposableArchitecture
import Foundation
import LabcordiOS

nonisolated enum ProtocolSource: String, Equatable, Sendable {
    case photos
    case file
    case recent
}

@Reducer
struct ProtocolRegistrationFeature {
    @ObservableState
    struct State: Equatable {
        var isSaving = false
        var pendingID: UUID?
        var hasFailed = false
    }

    enum Action: Equatable {
        case backTapped
        case skipTapped
        case saved(Result<ExperimentListEntry, SaveFailure>)
        case saveSucceeded(ExperimentListEntry)
        case retryTapped
        case dismissFailure
        case sourceTapped(ProtocolSource)
    }

    nonisolated enum SaveFailure: Error, Equatable, Sendable {
        case saving
    }

    @Dependency(\.experimentClient) var experimentClient
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .backTapped:
                return .none

            case .skipTapped:
                guard !state.isSaving, !state.hasFailed else { return .none }
                let identifier = state.pendingID ?? uuid()
                state.pendingID = identifier
                state.isSaving = true
                let date = now
                return .run { send in
                    do {
                        let entry = try await experimentClient.create(identifier, date)
                        await send(.saved(.success(entry)))
                    } catch {
                        await send(.saved(.failure(.saving)))
                    }
                }

            case let .saved(result):
                guard state.isSaving else { return .none }
                state.isSaving = false
                switch result {
                case let .success(entry):
                    state.pendingID = nil
                    return .send(.saveSucceeded(entry))
                case .failure:
                    state.hasFailed = true
                    return .none
                }

            case .retryTapped:
                state.hasFailed = false
                return .send(.skipTapped)

            case .dismissFailure:
                state.hasFailed = false
                return .none

            case .sourceTapped:
                return .none

            case .saveSucceeded:
                return .none
            }
        }
    }
}
