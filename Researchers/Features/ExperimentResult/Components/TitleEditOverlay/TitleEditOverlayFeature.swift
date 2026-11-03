import ComposableArchitecture
import Foundation
import LabcordiOS

@Reducer
struct TitleEditOverlayFeature {
    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        let originalTitle: String
        var title: String
        var isDiscardConfirmationPresented = false
        var isSaving = false
        var hasSaveFailed = false

        init(experimentID: UUID, originalTitle: String) {
            self.experimentID = experimentID
            self.originalTitle = originalTitle
            self.title = originalTitle
        }

        var canSave: Bool {
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && title != originalTitle
        }
    }

    enum Action: Equatable {
        case titleChanged(String)
        case dismissRequested
        case discardConfirmed
        case discardCancelled
        case saveTapped
        case saveSucceeded(ExperimentResultDetail)
        case saveFailed
        case saveFailureDismissed
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case dismiss
        case saved(ExperimentResultDetail)
    }

    @Dependency(\.experimentClient) var experimentClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .titleChanged(title):
                guard !state.isSaving else { return .none }
                state.title = String(title.prefix(60))
                return .none

            case .dismissRequested:
                guard !state.isSaving else { return .none }
                guard state.title != state.originalTitle else {
                    return .send(.delegate(.dismiss))
                }
                state.isDiscardConfirmationPresented = true
                return .none

            case .discardConfirmed:
                guard state.isDiscardConfirmationPresented, !state.isSaving else { return .none }
                state.isDiscardConfirmationPresented = false
                return .send(.delegate(.dismiss))

            case .discardCancelled:
                state.isDiscardConfirmationPresented = false
                return .none

            case .saveTapped:
                guard state.canSave, !state.isSaving,
                      !state.isDiscardConfirmationPresented else { return .none }
                state.isSaving = true
                state.hasSaveFailed = false
                let experimentID = state.experimentID
                let title = state.title
                return .run { send in
                    do {
                        let detail = try await experimentClient.updateTitle(experimentID, title)
                        await send(.saveSucceeded(detail))
                    } catch {
                        await send(.saveFailed)
                    }
                }

            case let .saveSucceeded(detail):
                guard state.isSaving else { return .none }
                state.isSaving = false
                guard detail.id == state.experimentID else {
                    state.hasSaveFailed = true
                    return .none
                }
                return .send(.delegate(.saved(detail)))

            case .saveFailed:
                guard state.isSaving else { return .none }
                state.isSaving = false
                state.hasSaveFailed = true
                return .none

            case .saveFailureDismissed:
                state.hasSaveFailed = false
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
