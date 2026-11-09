import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.appStorage("onboardingHasCompleted")) var hasCompletedOnboarding = false
        var onboarding: OnboardingFeature.State?
        var watchPendingStartID: UUID?
        var watchIsActive = false
        var watchRequestID: UUID?
        var watchCloseGate: WatchCloseCompletionGate<StackElementID>?
        var home = HomeFeature.State()
        var path = StackState<Path.State>()
        var reviewSaving = false
        var reviewSaveFailed = false
        var reviewAlreadySaved = false
        var reviewExitRequested = false
        var reviewPendingID: UUID?
        var reviewAnalysisJobID: UUID?
        var recentRegistrationID: StackElementID?
        var savedReview: ExperimentListEntry?
        var watchNotificationGate = WatchNotificationGate()
    }

    enum Action {
        case appeared
        case onboarding(OnboardingFeature.Action)
        case watchTask
        case watchEvent(PhoneWatchExperimentCoordinator.Event)
        case watchSceneChanged(Bool)
        case home(HomeFeature.Action)
        case path(StackActionOf<Path>)
        case closeRegistration(StackElementID)
        case registrationSucceeded(StackElementID, ExperimentListEntry)
        case showResult(StackElementID)
        case returnHome(StackElementID)
        case reviewSaved(
            StackElementID, Result<ExperimentListEntry, ProtocolRegistrationFeature.SaveFailure>
        )
        case reviewCleanupFinished(StackElementID, Bool)
        case reviewPreviouslySaved(StackElementID, ExperimentListEntry)
        case confirmAlreadySaved
        case openSavedReview
        case retryReviewSave
        case dismissReviewSaveFailure
        case confirmReviewExit
        case cancelReviewExit
        case timerNotificationTapped(UUID)
        case timerNotificationLoaded(UUID, UUID, ExperimentListEntry?)
    }

    @Dependency(\.experimentClient) var experimentClient
    @Dependency(\.protocolAnalysisJobManager) var jobManager
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now

    var body: some Reducer<State, Action> {
        Scope(state: \.home, action: \.home) { HomeFeature() }
        watchReducer

        Reduce { _, _ in .none }
            .ifLet(\.onboarding, action: \.onboarding) { OnboardingFeature() }

        Reduce { state, action in
            switch action {
            case .appeared, .onboarding:
                return handleLaunch(&state, action)

            case .timerNotificationTapped, .timerNotificationLoaded,
                 .watchTask, .watchEvent, .watchSceneChanged: return .none

            case .home(.addTapped):
                guard state.path.isEmpty, !state.home.list.isDeleting,
                      state.home.list.pendingDeletion == nil else { return .none }
                state.path.append(.registration(ProtocolRegistrationFeature.State()))
                return .send(.home(.list(.cancelLoad)))

            case let .home(.list(.experimentTapped(identifier))):
                guard state.path.isEmpty,
                      !state.home.list.isDeleting,
                      let entry = state.home.list.entries.first(where: { $0.id == identifier })
                else {
                    return .none
                }
                if entry.status == .completed {
                    state.path.append(
                        .result(ExperimentResultFeature.State(
                            experimentID: identifier,
                            isOpenedFromHome: true
                        ))
                    )
                } else {
                    state.path.append(
                        .session(ExperimentSessionFeature.State(experimentID: identifier))
                    )
                }
                return .send(.home(.list(.cancelLoad)))

            case let .path(.element(id: id, action: .registration(.backReady))):
                return .send(.closeRegistration(id))

            case let .closeRegistration(id):
                guard let registration = state.path[id: id, case: \.registration],
                      !registration.isSaving, !registration.importing,
                      registration.analysisID == nil, !registration.analysisStarting,
                      registration.invalidatingJobID == nil else {
                    return .none
                }
                state.path.pop(from: id)
                return .none

            case let .path(.element(id: id, action: .registration(.sourceTapped(.recent)))):
                guard state.path.ids.last == id,
                      let registration = state.path[id: id, case: \.registration],
                      !registration.importing, !registration.isSaving,
                      registration.analysisID == nil, !registration.analysisStarting,
                      registration.invalidatingJobID == nil else { return .none }
                state.recentRegistrationID = id
                state.path.append(.recent(RecentProtocolFeature.State()))
                return .none

            case let .path(.element(id: id, action: .recent(.backTapped))):
                guard state.path.ids.last == id else { return .none }
                state.path.pop(from: id)
                return .none

            case let .path(.element(id: id, action: .recent(.useSelected))):
                guard state.path.ids.last == id,
                      let recent = state.path[id: id, case: \.recent],
                      let entry = recent.entries.first(where: { $0.id == recent.selectedID }),
                      state.recentRegistrationID != nil else { return .none }
                let categories: [(ProtocolTermCategory, [String])] = [
                    (.materials, entry.materials), (.samples, entry.samples),
                    (.glossary, entry.glossaryTerms), (.units, entry.units)
                ]
                var terms: [ProtocolTermCategory: [ProtocolReviewTerm]] = [:]
                for (category, values) in categories {
                    terms[category] = values.map { ProtocolReviewTerm(id: uuid(), value: $0) }
                }
                state.reviewAnalysisJobID = nil
                state.path.append(.review(.init(
                    title: entry.title, timerSeconds: entry.timerSeconds, terms: terms
                )))
                return .none

            case let .path(.element(id: id, action: .registration(.showReview))):
                guard state.path.ids.last == id,
                      let registration = state.path[id: id, case: \.registration],
                      registration.analysisID == nil, !registration.analysisStarting,
                      registration.invalidatingJobID == nil,
                      !registration.successfulResults.isEmpty else { return .none }
                let seconds = registration.successfulResults.flatMap { item -> [Int] in
                    guard let text = item.extractedText else { return [] }
                    return ProtocolTimerExtractor.extract(from: text)
                }
                let terms = registration.extractedTerms.mapValues { values in
                    values.map { ProtocolReviewTerm(id: uuid(), value: $0) }
                }
                state.reviewAnalysisJobID = registration.analysisJobID
                state.path.append(.review(.init(title: "", timerSeconds: seconds, terms: terms)))
                return .none

            case let .path(.element(id: id, action: .review(.backTapped))):
                guard !state.reviewSaving, state.path.ids.last == id else { return .none }
                state.reviewExitRequested = true
                return .none

            case .confirmReviewExit:
                state.reviewExitRequested = false
                guard !state.reviewSaving, state.savedReview == nil,
                      let id = state.path.ids.last,
                      state.path[id: id, case: \.review] != nil else { return .none }
                state.reviewPendingID = nil
                state.path.pop(from: id)
                return .none

            case .cancelReviewExit:
                state.reviewExitRequested = false
                return .none

            case let .path(.element(id: id, action: .review(.registerTapped))):
                return registerReview(&state, id: id)

            case let .reviewPreviouslySaved(id, entry):
                guard state.reviewSaving, state.path.ids.last == id else { return .none }
                state.reviewSaving = false
                state.savedReview = entry
                state.reviewAlreadySaved = true
                return .none

            case .confirmAlreadySaved:
                guard state.reviewAlreadySaved else { return .none }
                state.reviewAlreadySaved = false
                guard let id = state.path.ids.last else { return .none }
                return .send(.path(.element(id: id, action: .review(.registerTapped))))

            case .openSavedReview:
                guard !state.reviewSaving, let entry = state.savedReview else { return .none }
                state.reviewAlreadySaved = false
                state.reviewSaveFailed = false
                state.savedReview = nil
                state.reviewPendingID = nil
                state.path.removeAll()
                if entry.status == .completed {
                    state.path.append(.result(.init(
                        experimentID: entry.id, isOpenedFromHome: true
                    )))
                } else {
                    state.path.append(.session(.init(experimentID: entry.id)))
                }
                return .send(.home(.list(.created(entry))))

            case let .reviewSaved(id, result):
                guard state.reviewSaving, state.path.ids.last == id else { return .none }
                state.reviewSaving = false
                switch result {
                case let .success(entry):
                    state.savedReview = entry
                    return .send(.path(.element(id: id, action: .review(.registerTapped))))
                case .failure:
                    state.reviewSaveFailed = true
                    return .none
                }

            case let .reviewCleanupFinished(id, succeeded):
                guard state.reviewSaving, state.path.ids.last == id,
                      state.savedReview != nil else { return .none }
                state.reviewSaving = false
                guard succeeded else {
                    state.reviewSaveFailed = true
                    return .none
                }
                return .send(.openSavedReview)

            case .retryReviewSave:
                state.reviewSaveFailed = false
                guard let id = state.path.ids.last,
                      state.path[id: id, case: \.review] != nil else { return .none }
                return .send(.path(.element(id: id, action: .review(.registerTapped))))

            case .dismissReviewSaveFailure:
                state.reviewSaveFailed = false
                return .none

            case let .path(.element(id: id, action: .registration(.saveSucceeded(entry)))):
                return .send(.registrationSucceeded(id, entry))

            case let .registrationSucceeded(id, entry):
                guard state.path.ids.last == id else { return .none }
                state.path.append(.session(ExperimentSessionFeature.State(experimentID: entry.id)))
                return .send(.home(.list(.created(entry))))

            case let .showResult(id):
                guard state.path.ids.last == id,
                      let experimentID = state.path[id: id, case: \.session]?.experimentID else {
                    return .none
                }
                state.path.append(
                    .result(ExperimentResultFeature.State(experimentID: experimentID))
                )
                return .none

            case let .path(.element(id: id, action: .result(.homeTapped))):
                guard state.path[id: id, case: \.result]?.isResuming == false else { return .none }
                return .send(.returnHome(id))

            case let .path(.element(id: id, action: .result(.resumeReady))):
                return openResumedSession(&state, id: id)

            case let .returnHome(id):
                guard state.path.ids.last == id else { return .none }
                state.path.removeAll()
                return .send(.home(.list(.load)))

            case .home, .path: return .none
            }
        }
        .forEach(\.path, action: \.path)
        watchCompletionNavigationReducer
        watchContextReducer
    }
}

extension AppFeature {
    func loadNotificationExperiment(
        _ state: inout State,
        experimentID: UUID
    ) -> Effect<Action> {
        let token = uuid()
        state.watchNotificationGate.begin(experimentID: experimentID, token: token)
        return .run { send in
            let entry = try? await experimentClient.load().first { $0.id == experimentID }
            await send(.timerNotificationLoaded(experimentID, token, entry))
        }
    }

    func openNotificationExperiment(
        _ state: inout State,
        experimentID: UUID,
        token: UUID,
        entry: ExperimentListEntry?
    ) -> Effect<Action> {
        guard state.watchNotificationGate.receive(
            experimentID: experimentID, token: token,
            watchRequestPending: watchWorkPending(state)
        ) == .open else { return .none }
        guard let entry, !state.reviewSaving else { return .none }
        if entry.status == .completed {
            if state.path.ids.last.flatMap({ state.path[id: $0, case: \.result] })?
                .experimentID == experimentID { return .none }
            state.path.removeAll()
            state.path.append(.result(.init(
                experimentID: experimentID, isOpenedFromHome: true
            )))
        } else {
            if state.path.ids.last.flatMap({ state.path[id: $0, case: \.session] })?
                .experimentID == experimentID { return .none }
            state.path.removeAll()
            state.path.append(.session(.init(experimentID: experimentID)))
        }
        return .send(.home(.list(.cancelLoad)))
    }

}

private extension AppFeature {
    func openResumedSession(_ state: inout State, id: StackElementID) -> Effect<Action> {
        guard var result = state.path[id: id, case: \.result], result.isResuming else {
            return .none
        }
        guard state.path.ids.last == id else {
            result.isResuming = false
            state.path[id: id, case: \.result] = result
            return .none
        }
        state.path.removeAll()
        state.path.append(.session(.init(experimentID: result.experimentID)))
        return .none
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
                if jobID != nil,
                   let existing = try await experimentClient.load().first(where: {
                       $0.id == identifier
                   }) {
                    await send(.reviewPreviouslySaved(id, existing))
                    return
                }
                let entry = try await experimentClient.createWithProtocol(
                    identifier, date, title, procedure
                )
                await send(.reviewSaved(id, .success(entry)))
            } catch {
                await send(.reviewSaved(id, .failure(.saving)))
            }
        }
    }
}
