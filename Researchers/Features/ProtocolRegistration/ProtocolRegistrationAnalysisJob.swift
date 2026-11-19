import ComposableArchitecture
import Foundation
import LabcordiOS

extension ProtocolInputAnalysisFeature {
    func reduceAnalysisJob(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .startAnalysis(id):
            return startAnalysis(id, state: &state)

        case let .analysisStartFinished(id, succeeded):
            return finishStartingAnalysis(id, succeeded: succeeded, state: &state)

        case let .restoreAnalysisJob(snapshot):
            return restoreAnalysisJob(snapshot, state: &state)

        case let .analysisJobUpdated(snapshot):
            guard state.analysisJobID == snapshot.id,
                  Set(state.selectedInputs.map(\.id)) == Set(snapshot.inputs.map(\.id))
            else { return .none }
            state.applyAnalysisProgress(snapshot)
            state.analysisMessage = snapshot.message
            state.analysisPaused = snapshot.status == .paused
            state.analysisResults = Dictionary(
                uniqueKeysWithValues: snapshot.results.map { ($0.id, $0) }
            )
            state.analysisTerms = snapshot.terms
            state.applyAnalysisPhase(snapshot.phase)
            let active = snapshot.status == .running || snapshot.status == .queued
            state.analysisID = active ? snapshot.id : nil
            state.analysisStartedAt = active ? snapshot.startedAt : nil
            state.showsAnalysisCompletion = snapshot.status == .completed
            state.analysisFailed = snapshot.status == .failed
            if snapshot.status == .cancelled { state.analysisCancellationRequested = false }
            return .none

        case let .analysisJobFailed(id):
            guard state.analysisJobID == id else { return .none }
            state.analysisID = nil
            state.analysisJobID = nil
            state.analysisStartedAt = nil
            state.analysisFailed = true
            state.analysisMessage = "분석을 시작하지 못했어요. 파일을 보관하고 다시 시도해 주세요."
            return .none

        default: return .none
        }
    }
}

private extension ProtocolInputAnalysisFeature {
    func restoreAnalysisJob(
        _ snapshot: ProtocolAnalysisJobSnapshot, state: inout State
    ) -> Effect<Action> {
        guard state.selectedInputs.isEmpty, !state.importing, state.analysisJobID == nil,
              state.invalidatingJobID == nil,
              snapshot.status != .cancelled else { return .none }
        for input in snapshot.inputs {
            let restored = ImportedProtocolInput.recovered(
                id: input.id, url: input.url, name: input.name
            )
            if input.isPhoto {
                state.importedPhotos.append(restored)
            } else {
                state.importedFile = restored
            }
        }
        state.analysisJobID = snapshot.id
        return .send(.analysisJobUpdated(snapshot))
    }

    func startAnalysis(_ id: UUID, state: inout State) -> Effect<Action> {
        guard !state.restoringAnalysis, state.analysisID == nil, !state.analysisStarting,
              state.invalidatingJobID == nil,
              !state.importing, !state.isSaving,
              !state.pendingInputs.isEmpty || state.analysisPaused else { return .none }
        let isResuming = state.analysisJobID != nil
        if !isResuming {
            state.analysisProgress = 0
            state.isCacheReplay = false
        }
        let inputs = state.selectedInputs.map { input in
            ProtocolAnalysisJobInput(
                id: input.id, url: input.url, name: input.name,
                isPhoto: state.importedPhotos.contains { $0.id == input.id }
            )
        }
        guard !inputs.isEmpty else { return .none }
        state.analysisStarting = true
        state.analysisResuming = isResuming
        state.afterStart = nil
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
        return .run { send in
            do {
                try await launchAnalysis(id, inputs: inputs, resuming: isResuming)
                await send(.analysisStartFinished(id, true))
            } catch {
                await send(.analysisStartFinished(id, false))
            }
        }
    }

    func launchAnalysis(
        _ id: UUID, inputs: [ProtocolAnalysisJobInput], resuming: Bool
    ) async throws {
        if resuming {
            try await jobManager.resume(id: id)
            return
        }
        #if DEBUG
        @Shared(.appStorage("protocolDemoCacheEnabled")) var cacheEnabled = false
        @Shared(.appStorage("protocolDemoCacheSeconds")) var cacheSeconds = 15
        let duration = cacheSeconds
        if cacheEnabled, let entries = await ProtocolDemoCache.checkpoints(for: inputs) {
            try await jobManager.startCached(id: id, entries: entries, seconds: duration)
            return
        }
        #endif
        try await jobManager.start(id: id, inputs: inputs)
    }

    func finishStartingAnalysis(
        _ id: UUID, succeeded: Bool, state: inout State
    ) -> Effect<Action> {
        guard state.analysisJobID == id, state.analysisStarting else { return .none }
        state.analysisStarting = false
        let next = state.afterStart
        let wasResuming = state.analysisResuming
        state.afterStart = nil
        state.analysisResuming = false
        if !succeeded {
            state.analysisCancellationRequested = false
            if let next {
                state.analysisID = nil
                if wasResuming {
                    return invalidateAnalysis(into: &state, then: next)
                }
                state.analysisJobID = nil
                return continueAfterInvalidation(next, state: &state)
            }
            if wasResuming {
                state.analysisID = nil
                state.analysisPaused = true
                state.analysisFailed = true
                state.analysisMessage = "분석을 이어서 진행하지 못했어요. 다시 시도해 주세요."
                return .none
            }
            return .send(.analysisJobFailed(id))
        }
        if let next {
            return invalidateAnalysis(into: &state, then: next)
        }
        return .none
    }
}

extension ProtocolInputAnalysisFeature.State {
    var analysisInput: ImportedProtocolInput? {
        selectedInputs.first { $0.id == analysisInputID }
    }

    var analysisInputNumber: Int? {
        selectedInputs.firstIndex { $0.id == analysisInputID }.map { $0 + 1 }
    }

    mutating func applyAnalysisProgress(_ snapshot: ProtocolAnalysisJobSnapshot) {
        isCacheReplay = snapshot.isCacheReplay
        guard isCacheReplay else {
            analysisProgress = max(analysisProgress, snapshot.progress)
            return
        }

        analysisProgress = snapshot.progress
        let orderedPhotoIDs = snapshot.inputs.filter(\.isPhoto).map(\.id)
        guard importedPhotos.map(\.id) != orderedPhotoIDs else { return }
        let photos = Dictionary(uniqueKeysWithValues: importedPhotos.map { ($0.id, $0) })
        importedPhotos = orderedPhotoIDs.compactMap { photos[$0] }
    }

    mutating func applyAnalysisPhase(_ phase: ProtocolAnalysisJobPhase) {
        switch phase {
        case .queued:
            analysisPhase = .queued
        case let .reading(inputID, phase):
            analysisInputID = inputID
            analysisPhase = .readingDocument(phase)
        case let .terms(inputID, progress):
            analysisInputID = inputID
            analysisPhase = .terms(progress)
        }
    }

    var hasAmbiguousTimers: Bool {
        successfulResults.contains { item in
            item.extractedText.map { ProtocolTimerExtractor.needsManualReview(in: $0) } ?? false
        }
    }

    var extractedTerms: [ProtocolTermCategory: [String]] {
        var seen: [ProtocolTermCategory: Set<String>] = [:]
        var merged: [ProtocolTermCategory: [String]] = [:]
        for item in successfulResults {
            guard let terms = analysisTerms[item.id] else { continue }
            let groups: [(ProtocolTermCategory, [String])] = [
                (.materials, terms.materials), (.samples, terms.samples),
                (.glossary, terms.glossaryTerms), (.units, terms.units)
            ]
            for (category, values) in groups {
                for value in values {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty,
                          seen[category, default: []]
                            .insert(ProtocolReviewTerm.comparisonKey(trimmed)).inserted
                    else { continue }
                    merged[category, default: []].append(trimmed)
                }
            }
        }
        return merged
    }
}
