import ComposableArchitecture
import Foundation
import LabcordiOS
import Photos

nonisolated enum ProtocolSource: String, Equatable, Sendable {
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
    enum PhotoAccessIssue: Equatable {
        case denied
        case restricted
    }

    @ObservableState
    struct State: Equatable {
        var pendingID: UUID?
        var hasFailed = false
        var requestingPhotoAccess = false
        var photoPickerPresented = false
        var photoAccessIssue: PhotoAccessIssue?
        var inputAnalysis = ProtocolInputAnalysisFeature.State()
        var analysisProgress = ProtocolAnalysisProgressFeature.State()
        var analysisCompletion = ProtocolAnalysisCompletionFeature.State()

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
        case analysisProgress(ProtocolAnalysisProgressFeature.Action)
        case analysisCompletion(ProtocolAnalysisCompletionFeature.Action)
        case backReady
        case createWithoutProtocol
        case skipTapped
        case saved(Result<ExperimentListEntry, SaveFailure>)
        case saveSucceeded(ExperimentListEntry)
        case retryTapped
        case dismissFailure
        case sourceTapped(ProtocolSource)
        case photosTapped
        case photoAccessRequested(PHAuthorizationStatus)
        case dismissPhotoAccessIssue
        case photoPickerDismissed
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
        Scope(state: \.analysisProgress, action: \.analysisProgress) {
            ProtocolAnalysisProgressFeature()
        }
        Scope(state: \.analysisCompletion, action: \.analysisCompletion) {
            ProtocolAnalysisCompletionFeature()
        }
        Reduce { state, action in
            switch action {
            case .photosTapped:
                guard !state.requestingPhotoAccess, !state.photoPickerPresented,
                      !state.isSaving, !state.importing, state.analysisID == nil,
                      state.invalidatingJobID == nil, !state.analysisStarting,
                      state.inputAnalysis.importedPhotos.count < 10 else { return .none }
                state.requestingPhotoAccess = true
                return .run { send in
                    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                    await send(.photoAccessRequested(status))
                }
            case let .photoAccessRequested(status):
                guard state.requestingPhotoAccess else { return .none }
                state.requestingPhotoAccess = false
                switch status {
                case .authorized, .limited:
                    state.photoPickerPresented = true
                case .denied:
                    state.photoAccessIssue = .denied
                case .restricted, .notDetermined:
                    state.photoAccessIssue = .restricted
                @unknown default:
                    state.photoAccessIssue = .restricted
                }
                return .none
            case .dismissPhotoAccessIssue:
                state.photoAccessIssue = nil
                return .none
            case .photoPickerDismissed:
                state.photoPickerPresented = false
                return .none
            case .analysisProgress(.delegate(.skip)):
                return .send(.skipTapped)
            case .analysisProgress(.delegate(.exit)), .analysisCompletion(.delegate(.exit)):
                return .send(.inputAnalysis(.backTapped))
            case .analysisCompletion(.delegate(.review)):
                return .send(.showReview)
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
            case .inputAnalysis, .analysisProgress, .analysisCompletion,
                 .backReady, .sourceTapped, .saveSucceeded, .showReview:
                return .none
            }
        }
    }
}
