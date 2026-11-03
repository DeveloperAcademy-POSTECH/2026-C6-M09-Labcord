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
    case termsPending
    case terms(ProtocolTermProgress)
}

@Reducer
struct ProtocolRegistrationFeature {
    @ObservableState
    struct State: Equatable {
        var isSaving = false
        var pendingID: UUID?
        var hasFailed = false
        var importing = false
        var importedPhotos: [ImportedProtocolInput] = []
        var importedFile: ImportedProtocolInput?
        var analysisJobID: UUID?
        var analysisMessage: String?
        var analysisPaused = false
        var analysisID: UUID?
        var analysisPhase = ProtocolAnalysisPhase.reading
        var analysisStartedAt: Date?
        var analysisInputID: UUID?
        var showsAnalysisCompletion = false
        var analysisCancellationRequested = false
        var analysisResults: [UUID: ProtocolAnalysisItem] = [:]
        /// 분석에 성공한 문서별 추출 용어입니다. 추출에 실패한 문서는 값이 없습니다.
        var analysisTerms: [UUID: ProtocolExtractedTerms] = [:]
        var analysisFailed = false

        var selectedInputs: [ImportedProtocolInput] {
            importedPhotos + (importedFile.map { [$0] } ?? [])
        }

        var pendingParsingInputs: [ImportedProtocolInput] {
            selectedInputs.filter { input in
                guard let item = analysisResults[input.id] else { return true }
                if case .failure = item.outcome { return true }
                return false
            }
        }

        var pendingInputs: [ImportedProtocolInput] {
            selectedInputs.filter { input in
                guard let item = analysisResults[input.id] else { return true }
                if case .failure = item.outcome { return true }
                return analysisTerms[input.id] == nil
            }
        }

        var successfulResults: [ProtocolAnalysisItem] {
            selectedInputs.compactMap { input in
                guard let item = analysisResults[input.id], case .success = item.outcome else {
                    return nil
                }
                return item
            }
        }

        var requiresReviewConfirmation: Bool {
            !pendingParsingInputs.isEmpty || termExtractionFailed || hasAmbiguousTimers
                || successfulResults.contains(where: \.hasWarnings)
                || analysisTerms.values.contains(where: \.usedFallback)
        }

        var termExtractionFailed: Bool {
            successfulResults.contains { analysisTerms[$0.id] == nil }
        }

    }

    enum Action: Equatable {
        case backTapped
        case skipTapped
        case saved(Result<ExperimentListEntry, SaveFailure>)
        case saveSucceeded(ExperimentListEntry)
        case retryTapped
        case dismissFailure
        case sourceTapped(ProtocolSource)
        case importStarted
        case importFinished
        case photoImported(ImportedProtocolInput)
        case fileImported(ImportedProtocolInput)
        case removePhoto(UUID)
        case removeFile
        case restoreAnalysisJob(ProtocolAnalysisJobSnapshot)
        case analysisJobUpdated(ProtocolAnalysisJobSnapshot)
        case analysisJobFailed(UUID)
        case startAnalysis(UUID)
        case analysisPhaseChanged(UUID, UUID, ProtocolAnalysisPhase)
        case analysisInputChanged(UUID, UUID)
        case analysisReadingProgress(UUID, UUID, ProtocolReadingPhase)
        case cancelAnalysis
        case analysisFinished(UUID, [ProtocolAnalysisItem]?, [UUID: ProtocolExtractedTerms])
        case showReview
        case clearImportedInputs
    }

    nonisolated enum SaveFailure: Error, Equatable, Sendable {
        case saving
    }

    @Dependency(\.experimentClient) var experimentClient
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now
    @Dependency(\.protocolAnalysisJobManager) var jobManager

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .backTapped:
                guard !state.importing, state.analysisID == nil else { return .none }
                let jobID = state.analysisJobID
                state.clearInputs()
                return .run { _ in
                    if let jobID { await jobManager.cancel(id: jobID) }
                }

            case .clearImportedInputs:
                let jobID = state.analysisJobID
                state.clearInputs()
                return .run { _ in
                    if let jobID { await jobManager.cancel(id: jobID) }
                }

            case .skipTapped:
                guard !state.isSaving, !state.hasFailed, !state.importing,
                      state.analysisID == nil else { return .none }
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
                    let jobID = state.analysisJobID
                    state.clearInputs()
                    return .run { send in
                        if let jobID { await jobManager.cancel(id: jobID) }
                        await send(.saveSucceeded(entry))
                    }
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

            case .importStarted:
                state.importing = true
                return .none

            case .importFinished:
                state.importing = false
                return .none

            case let .photoImported(input):
                state.analysisJobID = nil
                state.analysisMessage = nil
                state.importedPhotos.append(input)
                return .none

            case let .fileImported(input):
                state.analysisJobID = nil
                state.analysisMessage = nil
                if let id = state.importedFile?.id { state.clearAnalysis(for: id) }
                state.importedFile = input
                return .none

            case let .removePhoto(id):
                guard let index = state.importedPhotos.firstIndex(where: { $0.id == id }) else {
                    return .none
                }
                state.analysisJobID = nil
                state.analysisMessage = nil
                state.importedPhotos.remove(at: index)
                state.clearAnalysis(for: id)
                return .none

            case .removeFile:
                state.analysisJobID = nil
                state.analysisMessage = nil
                if let id = state.importedFile?.id { state.clearAnalysis(for: id) }
                state.importedFile = nil
                return .none

            case .restoreAnalysisJob, .analysisJobUpdated, .analysisJobFailed:
                return reduceAnalysisJob(into: &state, action: action)

            case let .startAnalysis(id):
                guard state.analysisID == nil, !state.importing, !state.isSaving,
                      !state.pendingInputs.isEmpty || state.analysisPaused else { return .none }
                state.analysisID = id
                state.analysisJobID = id
                state.analysisMessage = nil
                state.analysisPaused = false
                state.analysisStartedAt = now
                state.analysisInputID = state.pendingInputs.first?.id
                state.showsAnalysisCompletion = false
                state.analysisPhase = .reading
                state.analysisCancellationRequested = false
                state.analysisFailed = false
                return .none

            case let .analysisPhaseChanged(id, inputID, phase):
                guard state.analysisID == id, !state.analysisCancellationRequested,
                      state.selectedInputs.contains(where: { $0.id == inputID }) else {
                    return .none
                }
                state.analysisInputID = inputID
                state.analysisPhase = phase
                return .none

            case let .analysisInputChanged(id, inputID):
                guard state.analysisID == id, !state.analysisCancellationRequested,
                      state.selectedInputs.contains(where: { $0.id == inputID }) else {
                    return .none
                }
                state.analysisInputID = inputID
                return .none

            case let .analysisReadingProgress(id, inputID, phase):
                guard state.analysisID == id, !state.analysisCancellationRequested,
                      state.selectedInputs.contains(where: { $0.id == inputID }) else {
                    return .none
                }
                state.analysisInputID = inputID
                state.analysisPhase = .readingDocument(phase)
                return .none

            case .cancelAnalysis:
                guard state.analysisID != nil else { return .none }
                state.analysisCancellationRequested = true
                return .none

            case let .analysisFinished(id, items, terms):
                guard state.analysisID == id else { return .none }
                state.analysisID = nil
                state.analysisStartedAt = nil
                state.analysisInputID = nil
                state.analysisPhase = .reading
                if state.analysisCancellationRequested {
                    state.analysisCancellationRequested = false
                    return .none
                }
                guard let items else {
                    state.analysisFailed = true
                    return .none
                }
                let selectedIDs = Set(state.selectedInputs.map(\.id))
                for item in items where selectedIDs.contains(item.id) {
                    state.analysisResults[item.id] = item
                    state.analysisTerms[item.id] = terms[item.id]
                }
                state.analysisFailed = !state.pendingInputs.isEmpty
                state.showsAnalysisCompletion = !state.successfulResults.isEmpty
                    && state.pendingInputs.isEmpty
                return .none

            case .saveSucceeded:
                return .none

            case .showReview:
                return .none
            }
        }
    }
}

private extension ProtocolRegistrationFeature.State {
    mutating func clearInputs() {
        importedPhotos = []
        importedFile = nil
        analysisID = nil
        analysisJobID = nil
        analysisMessage = nil
        analysisPaused = false
        analysisStartedAt = nil
        analysisInputID = nil
        showsAnalysisCompletion = false
        analysisCancellationRequested = false
        analysisResults = [:]
        analysisTerms = [:]
        analysisFailed = false
        analysisPhase = .reading
    }

    mutating func clearAnalysis(for id: UUID) {
        showsAnalysisCompletion = false
        analysisResults[id] = nil
        analysisTerms[id] = nil
    }
}
