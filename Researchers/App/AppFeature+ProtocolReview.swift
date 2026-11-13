import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

extension AppFeature {
    func confirmReviewExit(_ state: inout State) -> Effect<Action> {
        state.reviewExitRequested = false
        guard !state.reviewSaving, state.savedReview == nil,
              let id = state.path.ids.last,
              state.path[id: id, case: \.review] != nil else { return .none }
        state.reviewPendingID = nil
        state.path.pop(from: id)
        state.reviewAnalysisJobID = nil
        guard let registrationID = state.path.ids.first(where: {
            state.path[id: $0, case: \.registration] != nil
        }) else { return .none }
        if let lastID = state.path.ids.last, lastID != registrationID {
            state.path.pop(from: lastID)
        }
        state.recentRegistrationID = nil
        return .send(.path(.element(
            id: registrationID, action: .registration(.inputAnalysis(.backTapped))
        )))
    }

    func registerReview(_ state: inout State, id: StackElementID) -> Effect<Action> {
        guard !state.reviewSaving, state.path.ids.last == id,
              let review = state.path[id: id, case: \.review], review.titleValid,
              review.timersValid, !review.hasUncommittedTerm else { return .none }
        if state.savedReview != nil {
            state.reviewSaving = true
            let jobID = state.reviewAnalysisJobID
            return .run { send in
                let success = if let jobID {
                    await jobManager.cancel(id: jobID)
                } else {
                    true
                }
                await send(.reviewCleanupFinished(id, success))
            }
        }
        let procedure = ExperimentProtocol(
            timerSeconds: review.timerSeconds,
            materials: review.terms[.materials, default: []].map(\.value),
            samples: review.terms[.samples, default: []].map(\.value),
            glossaryTerms: review.terms[.glossary, default: []].map(\.value),
            units: review.terms[.units, default: []].map(\.value)
        )
        let jobID = state.reviewAnalysisJobID
        let identifier = state.reviewPendingID ?? jobID ?? uuid()
        state.reviewPendingID = identifier
        state.reviewSaving = true
        state.reviewSaveFailed = false
        let date = now
        let title = review.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return .run { send in
            do {
                let experiments = try await experimentClient.load()
                if jobID != nil, let existing = try await experimentClient.load().first(where: {
                    $0.id == identifier
                }) {
                    await send(.reviewPreviouslySaved(id, existing))
                    return
                }
                let savedTitle = ExperimentTitle.unique(
                    title, existing: Set(experiments.filter { $0.id != identifier }.map(\.title))
                )
                let entry = try await experimentClient.createWithProtocol(
                    identifier, date, savedTitle, procedure)
                await send(.reviewSaved(id, .success(entry)))
            } catch {
                await send(.reviewSaved(id, .failure(.saving)))
            }
        }
    }
}
