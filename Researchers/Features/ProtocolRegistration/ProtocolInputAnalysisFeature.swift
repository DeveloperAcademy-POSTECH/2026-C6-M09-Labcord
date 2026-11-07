import ComposableArchitecture
import Foundation
import LabcordiOS

@Reducer
struct ProtocolInputAnalysisFeature {
    @ObservableState
    struct State: Equatable {
        var isSaving = false
        var importing = false
        var restoringAnalysis = true
        var recoveryFailed = false
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
        case observe
        case recoveryFailed
        case dismissRecoveryFailure
        case enteredBackground
        case backTapped
        case skipTapped
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
        case invalidationFinished(UUID, Bool, [ImportedProtocolInput])
        case retryInvalidation
        case discardFailedInvalidation
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case backReady
        case createWithoutProtocol
    }

    enum AfterInvalidation: Equatable {
        case back, skip, inputsChanged
    }

    private nonisolated enum CancelID { case observation }

    @Dependency(\.date.now) var now
    @Dependency(\.protocolAnalysisJobManager) var jobManager

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .observe:
                state.restoringAnalysis = true
                return .run { send in
                    do {
                        if let saved = try await jobManager.restore() {
                            try Task.checkCancellation()
                            await send(.restoreAnalysisJob(saved))
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(.recoveryFailed)
                    }
                    guard !Task.isCancelled else { return }
                    await send(.restoreCheckFinished)
                    for await update in await jobManager.updates() {
                        guard !Task.isCancelled else { return }
                        await send(.analysisJobUpdated(update))
                    }
                }
                .cancellable(id: CancelID.observation, cancelInFlight: true)

            case .recoveryFailed:
                state.recoveryFailed = true
                return .none

            case .dismissRecoveryFailure:
                state.recoveryFailed = false
                return .none

            case .enteredBackground:
                return .run { _ in await jobManager.enteredBackground() }

            case .backTapped:
                guard !state.restoringAnalysis, !state.isSaving, !state.importing,
                      state.invalidatingJobID == nil,
                      !state.analysisCancellationRequested else { return .none }
                return invalidateAnalysis(into: &state, then: .back)

            case .skipTapped:
                guard !state.restoringAnalysis, !state.isSaving, !state.importing,
                      state.invalidatingJobID == nil else { return .none }
                if state.analysisStarting {
                    state.afterStart = .skip
                    state.analysisCancellationRequested = true
                    return .none
                }
                return invalidateAnalysis(into: &state, then: .skip)

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

            case .delegate:
                return .none
            }
        }
    }
}

extension ProtocolInputAnalysisFeature {
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
            return .send(.delegate(.backReady))
        case .skip:
            state.clearInputs()
            state.isSaving = true
            return .send(.delegate(.createWithoutProtocol))
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

private extension ProtocolInputAnalysisFeature.State {
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
