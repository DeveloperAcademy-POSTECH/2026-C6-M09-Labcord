//
//  ExperimentPauseFeature.swift
//  Researchers
//
//  Created by 정홍섭 on 11/5/26.
//

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

        init(experimentID: UUID) {
            self.experimentID = experimentID
        }
    }

    enum Action: Equatable {
        case resumeTapped
        case returnHomeTapped
        case endTriggerChanged(Bool)
        case stopTapped
        case stopRejected
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

            case .stopRejected:
                state.isEndTriggered = false
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
