import ComposableArchitecture
import Foundation
import LabcordShared

extension WatchExperimentFeature {
    func navigate(
        _ proposed: WatchScreenSnapshot, discardTimerDraft: Bool = false, state: inout State
    ) -> Effect<Action> {
        guard proposed.isValid, state.isVisible, state.streamID != nil,
              restorePending(state: &state) else { return .none }
        if let pending = state.pending, pending.command.operation == .navigate {
            state.queuedNavigation = proposed.withRevision(state.phoneScreen?.revision ?? 0)
            state.queuedNavigationRequestID = pending.command.requestID
            state.queuedNavigationDiscardsTimerDraft = discardTimerDraft
            return .none
        }
        guard !state.blocksScreenTransition else {
            state.message = "진행 중인 기록과 요청을 확인한 뒤 화면을 이동할 수 있어요."
            return .none
        }
        guard state.isReachable else {
            state.message = "iPhone에 연결한 뒤 화면을 이동해주세요."
            return .none
        }
        let screen = proposed.withRevision(state.phoneScreen?.revision ?? 0, recordedAt: now)
        let command = WatchExperimentCommand(
            requestID: uuid(), operation: .navigate, experimentID: screen.experimentID,
            screen: screen, discardTimerDraft: discardTimerDraft ? true : nil
        )
        guard retainRequest(command, state: &state) else { return .none }
        state.pending = PendingRequest(command: command, responseID: command.requestID)
        state.clearMessageUnlessInterruptionUnconfirmed()
        return .merge(send(command), scheduleDeliveryTimeout(for: command.requestID))
    }

    func resolveQueuedNavigation(
        command: WatchExperimentCommand, response: WatchScreenSnapshot?, state: inout State
    ) {
        guard state.queuedNavigationRequestID == command.requestID else { return }
        state.queuedNavigationRequestID = nil
        guard let response, let proposed = command.screen,
              navigationMatches(response, proposed),
              state.phoneScreen?.revision == response.revision else {
            state.queuedNavigation = nil
            state.queuedNavigationDiscardsTimerDraft = false
            return
        }
        state.queuedNavigation = state.queuedNavigation?.withRevision(response.revision)
    }

    func acceptCompletedScreen(
        _ response: WatchExperimentResponse, command: WatchExperimentCommand, state: inout State
    ) -> Effect<Action> {
        let effect = response.screen.map { receiveScreen($0, state: &state) } ?? .none
        if command.operation == .navigate, let screen = response.screen,
           state.phoneScreen?.revision == screen.revision {
            state.deferredScreen = screen
        }
        resolveQueuedNavigation(command: command, response: response.screen, state: &state)
        return effect
    }

    func clearFailedNavigation(_ command: WatchExperimentCommand?, state: inout State) {
        if state.pending == nil { state.cleanupRequestID = nil }
        guard state.pending == nil, command?.operation == .navigate else { return }
        state.queuedNavigation = nil
        state.queuedNavigationRequestID = nil
        state.queuedNavigationDiscardsTimerDraft = false
    }

    func navigateToStage(
        _ stage: WatchScreenSnapshot.Stage, countdownEndsAt: Date? = nil,
        timerDraftSeconds: Int? = nil, discardTimerDraft: Bool = false, state: inout State
    ) -> Effect<Action> {
        guard let id = state.selectedID else { return .none }
        let destination: WatchScreenSnapshot.Destination =
            stage == .resumeConfirmation && state.snapshot?.experiment.status == .completed
                ? .result : .experiment
        return navigate(.init(
            destination: destination, experimentID: id, stage: stage,
            countdownEndsAt: countdownEndsAt, timerDraftSeconds: timerDraftSeconds
        ), discardTimerDraft: discardTimerDraft, state: &state)
    }

    private func navigationMatches(
        _ first: WatchScreenSnapshot, _ second: WatchScreenSnapshot
    ) -> Bool {
        first.destination == second.destination && first.experimentID == second.experimentID
            && first.stage == second.stage && first.countdownEndsAt == second.countdownEndsAt
            && first.timerDraftSeconds == second.timerDraftSeconds
    }

    func synchronizeTimerDraft(state: inout State) -> Effect<Action> {
        guard state.screen == .timerEditor else { return .none }
        let seconds = state.timerHours * 3600 + state.timerMinutes * 60 + state.timerSeconds
        return navigateToStage(.timerEditor, timerDraftSeconds: seconds, state: &state)
    }

    func navigateToExperiment(state: inout State) -> Effect<Action> {
        guard let id = state.selectedID else {
            return navigate(.init(destination: .home), state: &state)
        }
        return selectExperiment(id, state: &state)
    }

    func selectExperiment(_ id: UUID, state: inout State) -> Effect<Action> {
        let status = state.snapshots[id]?.experiment.status
            ?? state.experiments.first { $0.id == id }?.status ?? .ready
        let stage: WatchScreenSnapshot.Stage = switch status {
        case .ready: .preparation
        case .running: .active
        case .paused: .paused
        case .completed: .completed
        }
        return navigate(.init(
            destination: status == .completed ? .result : .experiment,
            experimentID: id, stage: stage
        ), state: &state)
    }

    func normalizeScreenForExperiment(state: inout State) -> Effect<Action> {
        guard let status = state.snapshot?.experiment.status else { return .none }
        let invalid: Bool = switch state.screen {
        case .permission, .countdown: status != .ready
        case .confirmPause, .timerEditor: status != .running
        case .confirmResume: status != .paused && status != .completed
        case .confirmComplete: status == .ready || status == .completed
        case .recordCleanup: status != .completed && state.pending?.command.operation != .complete
        default: false
        }
        guard invalid else { return .none }
        state.screen = .experiment
        state.isRequestingPermission = false
        state.permissionRequestID = nil
        state.countdownID = nil
        state.localCountdownEndsAt = nil
        state.startToken = nil
        return .merge(.cancel(id: CancelID.permission), .cancel(id: CancelID.countdown))
    }
}
