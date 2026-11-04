import ComposableArchitecture
import Foundation
import LabcordiOS

nonisolated enum ProtocolSource: String, Equatable, Sendable {
    case photos
    case file
    case recent
}

nonisolated enum ProtocolAnalysisPhase: Equatable, Sendable {
    case queued
    case reading
    case readingDocument(ProtocolReadingPhase)
    case terms(ProtocolTermProgress)
}

@Reducer
struct ProtocolRegistrationFeature {
    @ObservableState
    struct State: Equatable {
        var pendingID: UUID?
        var hasFailed = false
        var inputAnalysis = ProtocolInputAnalysisFeature.State()

        var isSaving: Bool {
            get { inputAnalysis.isSaving }
            set { inputAnalysis.isSaving = newValue }
        }
        var importing: Bool { inputAnalysis.importing }
        var analysisID: UUID? { inputAnalysis.analysisID }
        var analysisJobID: UUID? { inputAnalysis.analysisJobID }
        var analysisStarting: Bool { inputAnalysis.analysisStarting }
        var invalidatingJobID: UUID? { inputAnalysis.invalidatingJobID }
        var successfulResults: [ProtocolAnalysisItem] { inputAnalysis.successfulResults }
        var extractedTerms: [ProtocolTermCategory: [String]] { inputAnalysis.extractedTerms }
    }

    enum Action: Equatable {
        case inputAnalysis(ProtocolInputAnalysisFeature.Action)
        case backReady
        case createWithoutProtocol
        case skipTapped
        case saved(Result<ExperimentListEntry, SaveFailure>)
        case saveSucceeded(ExperimentListEntry)
        case retryTapped
        case dismissFailure
        case sourceTapped(ProtocolSource)
        case showReview
    }

    nonisolated enum SaveFailure: Error, Equatable, Sendable {
        case saving
    }

    @Dependency(\.experimentClient) var experimentClient
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now

    var body: some Reducer<State, Action> {
        Scope(state: \.inputAnalysis, action: \.inputAnalysis) {
            ProtocolInputAnalysisFeature()
        }
        Reduce { state, action in
            switch action {
            case .skipTapped:
                guard !state.isSaving, !state.hasFailed else { return .none }
                return .send(.inputAnalysis(.skipTapped))
            case .createWithoutProtocol:
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
            case .inputAnalysis(.delegate(.backReady)):
                return .send(.backReady)
            case .inputAnalysis(.delegate(.createWithoutProtocol)):
                return .send(.createWithoutProtocol)
            case .inputAnalysis, .backReady, .sourceTapped, .saveSucceeded, .showReview:
                return .none
            }
        }
    }
}
