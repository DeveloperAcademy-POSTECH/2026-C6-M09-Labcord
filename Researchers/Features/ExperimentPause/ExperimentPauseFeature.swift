import ComposableArchitecture
import Foundation
import LabcordiOS

@Reducer
struct ExperimentPauseFeature {
    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var isEndTriggered = false
        var isCompleting = false
        var completionAttempt = WatchCloseAttemptGate()
        var exitFailed = false
        var stopError: String?
        var isSavingWatchAudio = false

        init(experimentID: UUID) {
            self.experimentID = experimentID
        }
    }

    enum Action: Equatable {
        case resumeTapped
        case returnHomeTapped
        case endTriggerChanged(Bool)
        case stopTapped
        case stopRejected(String)
        case dismissStopError
        case saveWatchAudioAndStop
        case watchAudioSaved
        case watchAudioSaveFailed
        case completeRequested(UUID?)
        case completionSucceeded(UUID, UUID?)
        case completionFailed(UUID, UUID?)
        case homeExitStarted
        case homeExitFailed
        case dismissHomeExitFailure
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case resumeRequested
        case returnHomeRequested
        case stopRequested
        case completed(UUID, UUID?)
        case completionFailed(UUID?)
    }

    @Dependency(\.experimentClient) var experimentClient
    @Dependency(\.date.now) var now
    @Dependency(\.uuid) var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .resumeTapped:
                state.isEndTriggered = false
                return .send(.delegate(.resumeRequested))

            case .returnHomeTapped:
                return .send(.delegate(.returnHomeRequested))

            case let .endTriggerChanged(isTriggered):
                state.isEndTriggered = isTriggered
                return .none

            case .stopTapped:
                return .send(.delegate(.stopRequested))

            case let .stopRejected(message):
                state.isEndTriggered = false
                state.stopError = message
                return .none

            case .dismissStopError:
                state.stopError = nil
                return .none

            case .saveWatchAudioAndStop:
                guard !state.isSavingWatchAudio else { return .none }
                state.stopError = nil
                state.isSavingWatchAudio = true
                let experimentID = state.experimentID
                return .run { send in
                    do {
                        let audio = await PhoneWatchAudioService.shared
                        try await audio.saveReviewedRecordings(in: experimentID)
                        await send(.watchAudioSaved)
                    } catch {
                        await send(.watchAudioSaveFailed)
                    }
                }

            case .watchAudioSaved:
                state.isSavingWatchAudio = false
                return .send(.delegate(.stopRequested))

            case .watchAudioSaveFailed:
                state.isSavingWatchAudio = false
                state.stopError = "Watch 녹음을 저장하지 못했어요. 다시 시도해 주세요."
                return .none

            case let .completeRequested(requestID):
                guard !state.isCompleting else { return .none }
                state.isCompleting = true
                let attemptID = uuid()
                state.completionAttempt.begin(attemptID)
                let experimentID = state.experimentID
                let completedAt = now
                return .run { send in
                    do {
                        try await experimentClient.complete(experimentID, completedAt)
                        await send(.completionSucceeded(attemptID, requestID))
                    } catch {
                        await send(.completionFailed(attemptID, requestID))
                    }
                }

            case let .completionSucceeded(attemptID, requestID):
                guard state.completionAttempt.accept(attemptID) else { return .none }
                state.isCompleting = false
                return .send(.delegate(.completed(attemptID, requestID)))

            case let .completionFailed(attemptID, requestID):
                guard state.completionAttempt.accept(attemptID) else { return .none }
                state.isCompleting = false
                state.isEndTriggered = false
                if requestID == nil { state.stopError = "실험을 저장하지 못했어요. 다시 시도해 주세요." }
                return .send(.delegate(.completionFailed(requestID)))

            case .homeExitStarted:
                state.exitFailed = false
                return .none

            case .homeExitFailed:
                state.exitFailed = true
                return .none

            case .dismissHomeExitFailure:
                state.exitFailed = false
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
