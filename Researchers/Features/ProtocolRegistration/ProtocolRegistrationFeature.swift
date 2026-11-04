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
        var isSaving = false
        var pendingID: UUID?
        var hasFailed = false
        var importing = false
        var restoringAnalysis = true
        var importedPhotos: [ImportedProtocolInput] = []
        var importedFile: ImportedProtocolInput?
        var analysisJobID: UUID?
        var invalidatingJobID: UUID?
        var invalidationFailed = false
        var afterInvalidation: AfterInvalidation?
        var analysisMessage: String?
        var analysisPaused = false
        var analysisID: UUID?
        var analysisStarting = false
        var analysisResuming = false
        var afterStart: AfterInvalidation?
        var analysisPhase = ProtocolAnalysisPhase.reading
        var analysisStartedAt: Date?
        var analysisInputID: UUID?
        var showsAnalysisCompletion = false
        var analysisCancellationRequested = false
        var analysisResults: [UUID: ProtocolAnalysisItem] = [:]
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
        case backReady
        case createWithoutProtocol
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
        case restoreCheckFinished
        case analysisJobUpdated(ProtocolAnalysisJobSnapshot)
        case analysisJobFailed(UUID)
        case startAnalysis(UUID)
        case analysisStartFinished(UUID, Bool)
        case cancelAnalysis
        case showReview
        case clearImportedInputs
        case invalidationFinished(UUID, Bool, [ImportedProtocolInput])
        case retryInvalidation
        case discardFailedInvalidation
    }

    enum AfterInvalidation: Equatable {
        case back, skip, clear, inputsChanged
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
                guard !state.restoringAnalysis, !state.importing, state.analysisID == nil,
                      state.invalidatingJobID == nil else { return .none }
                return invalidateAnalysis(into: &state, then: .back)

            case .backReady:
                return .none

            case .clearImportedInputs:
                guard state.invalidatingJobID == nil else { return .none }
                if state.analysisStarting {
                    state.afterStart = .clear
                    state.analysisCancellationRequested = true
                    return .none
                }
                return invalidateAnalysis(into: &state, then: .clear)

            case .skipTapped:
                guard !state.restoringAnalysis, !state.isSaving, !state.hasFailed,
                      !state.importing, state.invalidatingJobID == nil else { return .none }
                if state.analysisStarting {
                    state.afterStart = .skip
                    state.analysisCancellationRequested = true
                    return .none
                }
                return invalidateAnalysis(into: &state, then: .skip)

            case .createWithoutProtocol:
                state.clearInputs()
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

            case .restoreCheckFinished:
                state.restoringAnalysis = false
                return .none

            case .importStarted:
                state.importing = true
                return .none

            case .importFinished:
                state.importing = false
                return .none

            case let .photoImported(input):
                state.analysisMessage = nil
                state.importedPhotos.append(input)
                return invalidateAnalysis(into: &state)

            case let .fileImported(input):
                state.analysisMessage = nil
                if let id = state.importedFile?.id { state.clearAnalysis(for: id) }
                state.importedFile = input
                return invalidateAnalysis(into: &state)

            case let .removePhoto(id):
                guard let index = state.importedPhotos.firstIndex(where: { $0.id == id }) else {
                    return .none
                }
                state.analysisMessage = nil
                state.importedPhotos.remove(at: index)
                state.clearAnalysis(for: id)
                return invalidateAnalysis(into: &state)

            case .removeFile:
                state.analysisMessage = nil
                if let id = state.importedFile?.id { state.clearAnalysis(for: id) }
                state.importedFile = nil
                return invalidateAnalysis(into: &state)

            case let .invalidationFinished(id, succeeded, preserved):
                guard state.invalidatingJobID == id else { return .none }
                let copies = Dictionary(uniqueKeysWithValues: preserved.map { ($0.id, $0) })
                state.importedPhotos = state.importedPhotos.map { copies[$0.id] ?? $0 }
                if let file = state.importedFile {
                    state.importedFile = copies[file.id] ?? file
                }
                if succeeded {
                    state.invalidatingJobID = nil
                    state.invalidationFailed = false
                    state.analysisID = nil
                    state.analysisCancellationRequested = false
                    let next = state.afterInvalidation
                    state.afterInvalidation = nil
                    return continueAfterInvalidation(next, state: &state)
                }
                state.analysisID = nil
                state.analysisCancellationRequested = false
                state.invalidationFailed = true
                return .none

            case .retryInvalidation:
                guard let id = state.invalidatingJobID, state.invalidationFailed else {
                    return .none
                }
                state.invalidationFailed = false
                return invalidateEffect(
                    id: id, inputs: state.selectedInputs, then: state.afterInvalidation
                )

            case .discardFailedInvalidation:
                guard let id = state.invalidatingJobID, state.invalidationFailed else {
                    return .none
                }
                state.invalidationFailed = false
                state.afterInvalidation = .back
                return invalidateEffect(id: id, inputs: [], then: .back)

            case .restoreAnalysisJob, .analysisJobUpdated, .analysisJobFailed,
                 .startAnalysis, .analysisStartFinished:
                return reduceAnalysisJob(into: &state, action: action)

            case .cancelAnalysis:
                guard state.analysisID != nil else { return .none }
                state.analysisCancellationRequested = true
                return .none

            case .saveSucceeded:
                return .none

            case .showReview:
                return .none
            }
        }
    }
}

extension ProtocolRegistrationFeature {
    func invalidateAnalysis(
        into state: inout State, then next: AfterInvalidation? = nil
    ) -> Effect<Action> {
        guard state.invalidatingJobID == nil else { return .none }
        if state.analysisStarting {
            state.afterStart = next ?? .inputsChanged
            state.analysisCancellationRequested = true
            return .none
        }
        guard let id = state.analysisJobID else {
            return continueAfterInvalidation(next, state: &state)
        }
        state.analysisJobID = nil
        state.invalidatingJobID = id
        state.afterInvalidation = next
        state.analysisPaused = false
        state.invalidationFailed = false
        state.analysisCancellationRequested = state.analysisID != nil
        return invalidateEffect(id: id, inputs: state.selectedInputs, then: next)
    }

    func invalidateEffect(
        id: UUID, inputs: [ImportedProtocolInput], then next: AfterInvalidation?
    ) -> Effect<Action> {
        .run { send in
            do {
                var copies: [ImportedProtocolInput] = []
                if next == nil || next == .inputsChanged {
                    for input in inputs { copies.append(try await input.preservedCopy()) }
                }
                let succeeded = await jobManager.cancel(id: id)
                await send(.invalidationFinished(id, succeeded, copies))
            } catch {
                await send(.invalidationFinished(id, false, []))
            }
        }
    }

    func continueAfterInvalidation(
        _ next: AfterInvalidation?, state: inout State
    ) -> Effect<Action> {
        switch next {
        case .back:
            state.clearInputs()
            return .send(.backReady)
        case .skip:
            return .send(.createWithoutProtocol)
        case .clear:
            state.clearInputs()
            return .none
        case .inputsChanged, nil:
            state.analysisFailed = state.selectedInputs.contains { input in
                guard let item = state.analysisResults[input.id] else { return false }
                if case .failure = item.outcome { return true }
                return false
            }
            return .none
        }
    }

}

private extension ProtocolRegistrationFeature.State {
    mutating func clearInputs() {
        importedPhotos = []
        importedFile = nil
        analysisID = nil
        analysisStarting = false
        analysisResuming = false
        afterStart = nil
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
