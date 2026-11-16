import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

enum WatchSplashPhase: Equatable {
    case waiting
    case showing
    case ready
}

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.appStorage("onboardingHasCompleted")) var hasCompletedOnboarding = false
        var onboarding: OnboardingFeature.State?
        var watchPendingStartID: UUID?
        var watchSplashPhase = WatchSplashPhase.waiting
        var screenNavigation: WatchExperimentCommand?
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
        var pendingLiveActivityExperimentID: UUID?
        var readyLiveActivityExperimentID: UUID?
    }

    enum Action {
        case appeared
        case openLiveActivityExperiment(UUID)
        case liveActivityExperimentLoaded(UUID, Bool)
        case onboarding(OnboardingFeature.Action)
        case screenNavigationLoaded(UUID, WatchExperimentState?, WatchExperimentError?)
        case watchTask
        case watchEvent(PhoneWatchExperimentCoordinator.Event)
        case watchSceneChanged(Bool)
        case watchSplashChanged(Bool)
        case restoreSettingsSession
        case settingsSessionLoaded(UUID, Bool)
        case home(HomeFeature.Action)
        case path(StackActionOf<Path>)
        case closeRegistration(StackElementID)
        case registrationSucceeded(StackElementID, ExperimentListEntry)
        case showResult(StackElementID)
        case returnHome(StackElementID)
        case reviewSaved(
            StackElementID, Result<ExperimentListEntry, ProtocolRegistrationFeature.SaveFailure>)
        case reviewCleanupFinished(StackElementID, Bool)
        case reviewPreviouslySaved(StackElementID, ExperimentListEntry)
        case confirmAlreadySaved
        case openSavedReview
        case retryReviewSave
        case dismissReviewSaveFailure
        case confirmReviewExit
        case cancelReviewExit
    }

    @Dependency(\.experimentClient) var experimentClient
    @Dependency(\.protocolAnalysisJobManager) var jobManager
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now
    @Dependency(\.timerLiveActivityClient) var timerLiveActivityClient

    var body: some Reducer<State, Action> {
        Scope(state: \.home, action: \.home) { HomeFeature() }
        watchReducer
        gestureGuideReducer
        screenNavigationReducer
        settingsReturnReducer

        Reduce { _, _ in .none }
            .ifLet(\.onboarding, action: \.onboarding) { OnboardingFeature() }

        appReducer
            .forEach(\.path, action: \.path)
        watchCompletionNavigationReducer
        watchContextReducer
        watchPendingOpenReducer
    }
}

private extension AppFeature {
    var appReducer: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared, .onboarding:
                return handleLaunch(&state, action)

            case let .openLiveActivityExperiment(experimentID):
                guard state.hasCompletedOnboarding else { return .none }
                state.pendingLiveActivityExperimentID = experimentID
                state.readyLiveActivityExperimentID = nil
                return .run { send in
                    let exists = (try? await experimentClient.load())?.contains {
                        $0.id == experimentID && $0.status != .completed
                    } == true
                    await send(.liveActivityExperimentLoaded(experimentID, exists))
                }

            case let .liveActivityExperimentLoaded(experimentID, exists):
                guard state.pendingLiveActivityExperimentID == experimentID else { return .none }
                state.pendingLiveActivityExperimentID = nil
                guard exists else { return .none }
                state.readyLiveActivityExperimentID = experimentID
                return openReadyLiveActivityExperiment(&state)

            case let .watchSceneChanged(active):
                return active ? openReadyLiveActivityExperiment(&state) : .none

            case let .watchSplashChanged(ready):
                state.watchSplashPhase = ready ? .ready : .waiting
                return .none

            case .screenNavigationLoaded, .watchTask, .watchEvent,
                 .restoreSettingsSession, .settingsSessionLoaded: return .none

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
                    state.path.append(.session(.init(experimentID: identifier)))
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
                return confirmReviewExit(&state)

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
                state.path.append(.result(.init(experimentID: experimentID)))
                return .none

            case let .path(.element(id: id, action: .result(.homeTapped))):
                guard state.path[id: id, case: \.result]?.isResuming == false else { return .none }
                return .send(.returnHome(id))

            case let .path(.element(id: id, action: .result(.resumeSucceeded))):
                guard state.path.ids.last == id,
                      let experimentID = state.path[id: id, case: \.result]?.experimentID else {
                    return .none
                }
                state.path.removeAll()
                state.path.append(.session(.init(experimentID: experimentID)))
                return .send(.home(.list(.load)))

            case let .returnHome(id):
                guard state.path.ids.last == id else { return .none }
                let session = state.path[id: id, case: \.session]
                state.path.removeAll()
                guard let session, session.homeExitAttempt.lastAcceptedID != nil else {
                    return .send(.home(.list(.load)))
                }
                let experimentID = session.experimentID
                let experimentTitle = session.detail?.title ?? ""
                let timers = runningTimers(in: session.timer.timerCollection, at: now)
                return .merge(
                    .send(.home(.list(.load))),
                    .run { _ in
                        await timerLiveActivityClient.synchronize(
                            experimentID, experimentTitle, timers
                        )
                    }
                )

            case let .path(.element(id: id, action: .session(.detailLoaded(_)))):
                guard let experimentID = state.path[id: id, case: \.session]?.experimentID
                else { return .none }
                return .run { _ in
                    await timerLiveActivityClient.dismissCompleted(experimentID)
                }

            case .home, .path: return .none
            }
        }
    }

    func openReadyLiveActivityExperiment(_ state: inout State) -> Effect<Action> {
        guard state.watchIsActive,
              let experimentID = state.readyLiveActivityExperimentID else { return .none }
        state.readyLiveActivityExperimentID = nil
        guard !state.reviewSaving, state.watchRequestID == nil,
              state.watchPendingStartID == nil else { return .none }
        if let id = state.path.ids.last,
           state.path[id: id, case: \.session]?.experimentID == experimentID {
            return .none
        }
        state.path.removeAll()
        state.path.append(.session(.init(experimentID: experimentID)))
        return .send(.home(.list(.cancelLoad)))
    }

    func runningTimers(
        in collection: ExperimentTimerCollection, at date: Date
    ) -> [TimerActivityAttributes.ContentState] {
        let timers: [TimerActivityAttributes.ContentState] =
            collection.timers.compactMap { timer in
                guard timer.status == .running else { return nil }
                let pausedDuration = timer.pauseIntervals.reduce(0.0) { total, interval in
                    total + max(0, interval.resumedAt?.timeIntervalSince(interval.pausedAt) ?? 0)
                }
                let endsAt = timer.startedAt.addingTimeInterval(
                    TimeInterval(timer.durationSeconds) + pausedDuration
                )
                guard endsAt > date else { return nil }
                return TimerActivityAttributes.ContentState(
                    timerID: timer.id,
                    endsAt: endsAt,
                    durationSeconds: timer.durationSeconds
                )
            }
        return timers.sorted { left, right in
            if left.endsAt != right.endsAt { return left.endsAt < right.endsAt }
            return left.timerID.uuidString < right.timerID.uuidString
        }
    }
}
