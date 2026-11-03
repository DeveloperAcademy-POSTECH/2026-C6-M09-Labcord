import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

@Reducer
struct AppFeature {
    @Reducer
    enum Path {
        case registration(ProtocolRegistrationFeature)
        case recent(RecentProtocolFeature)
        case review(ProtocolReviewFeature)
        case session(ExperimentSessionFeature)
        case result(ExperimentResultFeature)
    }

    @ObservableState
    struct State: Equatable {
        var home = HomeFeature.State()
        var path = StackState<Path.State>()
        var reviewSaving = false
        var reviewSaveFailed = false
        var reviewExitRequested = false
        var reviewPendingID: UUID?
        var reviewRegistrationID: StackElementID?
        var recentRegistrationID: StackElementID?
    }

    enum Action {
        case home(HomeFeature.Action)
        case path(StackActionOf<Path>)
        case closeRegistration(StackElementID)
        case registrationSucceeded(StackElementID, ExperimentListEntry)
        case showResult(StackElementID)
        case returnHome(StackElementID)
        case reviewSaved(
            StackElementID, Result<ExperimentListEntry, ProtocolRegistrationFeature.SaveFailure>
        )
        case retryReviewSave
        case dismissReviewSaveFailure
        case confirmReviewExit
        case cancelReviewExit
    }

    @Dependency(\.experimentClient) var experimentClient
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now

    var body: some Reducer<State, Action> {
        Scope(state: \.home, action: \.home) { HomeFeature() }

        Reduce { state, action in
            switch action {
            case .home(.addTapped):
                guard state.path.isEmpty, !state.home.list.isDeleting,
                      state.home.list.pendingDeletion == nil else { return .none }
                state.path.append(.registration(ProtocolRegistrationFeature.State()))
                state.reviewPendingID = nil
                state.reviewRegistrationID = nil
                return .send(.home(.list(.cancelLoad)))

            case let .home(.list(.experimentTapped(identifier))):
                guard state.path.isEmpty, !state.home.list.isDeleting,
                      state.home.list.entries.contains(where: { $0.id == identifier }) else {
                    return .none
                }
                state.path.append(
                    .session(ExperimentSessionFeature.State(experimentID: identifier))
                )
                return .send(.home(.list(.cancelLoad)))

            case let .path(.element(id: id, action: .registration(.backTapped))):
                return .send(.closeRegistration(id))

            case let .closeRegistration(id):
                guard let registration = state.path[id: id, case: \.registration],
                      !registration.isSaving, !registration.importing,
                      registration.analysisID == nil else {
                    return .none
                }
                state.path.pop(from: id)
                return .none

            case let .path(.element(id: id, action: .registration(.saveSucceeded(entry)))):
                return .send(.registrationSucceeded(id, entry))

            case let .path(.element(id: id, action: .registration(.sourceTapped(.recent)))):
                guard state.path.ids.last == id,
                      let registration = state.path[id: id, case: \.registration],
                      !registration.importing, !registration.isSaving,
                      registration.analysisID == nil else { return .none }
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
                      let registrationID = state.recentRegistrationID else { return .none }
                let categories: [(ProtocolTermCategory, [String])] = [
                    (.materials, entry.materials), (.samples, entry.samples),
                    (.glossary, entry.glossaryTerms), (.units, entry.units)
                ]
                var terms: [ProtocolTermCategory: [ProtocolReviewTerm]] = [:]
                for (category, values) in categories {
                    terms[category] = values.map { ProtocolReviewTerm(id: uuid(), value: $0) }
                }
                state.reviewRegistrationID = registrationID
                state.path.append(.review(ProtocolReviewFeature.State(
                    title: entry.title, timerSeconds: entry.timerSeconds, terms: terms
                )))
                return .none

            case let .path(.element(id: id, action: .registration(.showReview))):
                guard state.path.ids.last == id,
                      let registration = state.path[id: id, case: \.registration],
                      registration.analysisID == nil,
                      !registration.successfulResults.isEmpty else { return .none }
                var seenSeconds = Set<Int>()
                let seconds = registration.successfulResults.flatMap { item -> [Int] in
                    guard let text = item.extractedText else { return [] }
                    return ProtocolTimerExtractor.extract(from: text)
                }.filter { seenSeconds.insert($0).inserted }
                let terms = registration.extractedTerms.mapValues { values in
                    values.map { ProtocolReviewTerm(id: uuid(), value: $0) }
                }
                state.reviewRegistrationID = id
                state.path.append(.review(ProtocolReviewFeature.State(
                    title: "", timerSeconds: seconds, terms: terms
                )))
                return .none

            case let .path(.element(id: id, action: .review(.backTapped))):
                guard !state.reviewSaving, state.path.ids.last == id else { return .none }
                state.reviewExitRequested = true
                return .none

            case .confirmReviewExit:
                state.reviewExitRequested = false
                guard !state.reviewSaving, let id = state.path.ids.last,
                      state.path[id: id, case: \.review] != nil else { return .none }
                state.path.pop(from: id)
                return .none

            case .cancelReviewExit:
                state.reviewExitRequested = false
                return .none

            case let .path(.element(id: id, action: .review(.registerTapped))):
                guard !state.reviewSaving, state.path.ids.last == id,
                      let review = state.path[id: id, case: \.review], review.titleValid,
                      !review.hasUncommittedTerm else {
                    return .none
                }
                let procedure = ExperimentProtocol(
                    timerSeconds: review.timerSeconds,
                    materials: review.terms[.materials, default: []].map(\.value),
                    samples: review.terms[.samples, default: []].map(\.value),
                    glossaryTerms: review.terms[.glossary, default: []].map(\.value),
                    units: review.terms[.units, default: []].map(\.value)
                )
                let identifier = state.reviewPendingID ?? uuid()
                state.reviewPendingID = identifier
                state.reviewSaving = true
                state.reviewSaveFailed = false
                let date = now
                let title = review.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return .run { send in
                    do {
                        let entry = try await experimentClient.createWithProtocol(
                            identifier, date, title, procedure
                        )
                        await send(.reviewSaved(id, .success(entry)))
                    } catch {
                        await send(.reviewSaved(id, .failure(.saving)))
                    }
                }

            case let .reviewSaved(id, result):
                guard state.reviewSaving else { return .none }
                state.reviewSaving = false
                switch result {
                case let .success(entry):
                    guard state.path.ids.last == id else { return .send(.home(.list(.load))) }
                    state.reviewPendingID = nil
                    state.path.append(.session(
                        ExperimentSessionFeature.State(experimentID: entry.id)
                    ))
                    if let registrationID = state.reviewRegistrationID {
                        return .merge(
                            .send(.path(.element(id: registrationID,
                                                action: .registration(.clearImportedInputs)))),
                            .send(.home(.list(.created(entry))))
                        )
                    }
                    return .send(.home(.list(.created(entry))))
                case .failure:
                    state.reviewSaveFailed = true
                    return .none
                }

            case .retryReviewSave:
                state.reviewSaveFailed = false
                guard let id = state.path.ids.last,
                      state.path[id: id, case: \.review] != nil else { return .none }
                return .send(.path(.element(id: id, action: .review(.registerTapped))))

            case .dismissReviewSaveFailure:
                state.reviewSaveFailed = false
                return .none

            case let .registrationSucceeded(id, entry):
                guard state.path.ids.last == id else { return .none }
                state.path.append(.session(ExperimentSessionFeature.State(experimentID: entry.id)))
                return .send(.home(.list(.created(entry))))

            case let .path(.element(id: id, action: .session(.stopCompleted))):
                return .send(.showResult(id))

            case let .path(.element(id: id, action: .session(.homeExitCompleted))):
                return .send(.returnHome(id))

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
                return .send(.returnHome(id))

            case let .returnHome(id):
                guard state.path.ids.last == id else { return .none }
                state.path.removeAll()
                return .send(.home(.list(.load)))

            case .home, .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}

extension AppFeature.Path.State: Equatable {}
