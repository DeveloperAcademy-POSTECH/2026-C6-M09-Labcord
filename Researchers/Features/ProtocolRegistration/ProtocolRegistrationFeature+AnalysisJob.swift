import ComposableArchitecture
import Foundation
import LabcordiOS

extension ProtocolRegistrationFeature {
    func reduceAnalysisJob(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .restoreAnalysisJob(snapshot):
            guard state.selectedInputs.isEmpty, state.analysisJobID == nil,
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

        case let .analysisJobUpdated(snapshot):
            guard state.analysisJobID == snapshot.id,
                  Set(state.selectedInputs.map(\.id)) == Set(snapshot.inputs.map(\.id))
            else { return .none }
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

extension ProtocolRegistrationFeature.State {
    var analysisInput: ImportedProtocolInput? {
        selectedInputs.first { $0.id == analysisInputID }
    }

    var analysisInputNumber: Int? {
        selectedInputs.firstIndex { $0.id == analysisInputID }.map { $0 + 1 }
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

    /// 현재 선택된 문서 중 분석에 성공한 문서의 용어를 분류별로 합칩니다.
    /// 같은 용어는 먼저 나온 분류에만 남깁니다.
    var extractedTerms: [ProtocolTermCategory: [String]] {
        var seen = Set<String>()
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
                          seen.insert(ProtocolReviewTerm.comparisonKey(trimmed)).inserted
                    else { continue }
                    merged[category, default: []].append(trimmed)
                }
            }
        }
        return merged
    }
}
