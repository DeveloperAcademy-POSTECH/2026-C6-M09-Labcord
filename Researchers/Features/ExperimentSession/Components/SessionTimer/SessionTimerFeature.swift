import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

@Reducer
struct SessionTimerFeature {
    enum TimerTab: Equatable {
        case configured
        case active
    }

    struct TimerChange: Equatable {
        let timer: ExperimentTimer
        let endedAt: Date?
    }

    struct PendingSave: Equatable {
        let changes: [TimerChange]
        let collection: ExperimentTimerCollection
        var dismissedTimerID: UUID?
        var clearsTimerDraft = false
    }

    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var selectedTimerTab: TimerTab = .configured
        var isEditorPresented = false
        var draftSeconds = 600
        var initialDraftSeconds = 600
        var timerSeconds: [Int] = []
        var mode: ExperimentMode = .free
        var timerCollection = ExperimentTimerCollection()
        var isConfigured = false
        var pendingSave: PendingSave?
        var isSaving = false
        var saveFailed = false
        var isClosing = false
        var watchRequest: WatchExperimentCommand?

        init(experimentID: UUID = UUID()) {
            self.experimentID = experimentID
        }
    }

    enum Action: Equatable {
        case configure(mode: ExperimentMode, timerSeconds: [Int], timers: [ExperimentTimer])
        case timerTabSelected(TimerTab)
        case editorPresented(Bool)
        case draftSecondsChanged(Int)
        case timerStarted(Int)
        case customTimerStarted(Int)
        case timerPaused(UUID)
        case allTimersPaused
        case timerResumed(UUID)
        case timerDeleted(UUID)
        case timerTick(Date)
        case timerSaved
        case timerSaveFailed
        case retrySaveTapped
        case watchCommand(WatchExperimentCommand)
        case delegate(WatchExperimentResponse)
    }

    @Dependency(\.experimentClient) var experimentClient
    @Dependency(\.date.now) var now
    @Dependency(\.uuid) var uuid

    private nonisolated enum CancelID: Hashable, Sendable {
        case timerTick
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .watchCommand(command):
                guard command.experimentID == state.experimentID, state.isConfigured,
                      state.canModifyTimers else {
                    return .send(.delegate(WatchExperimentResponse(
                        requestID: command.requestID, phase: .failed, error: .invalidState
                    )))
                }
                do {
                    let mutation = try WatchTimerMutation.prepare(
                        command, timers: state.timerCollection.timers, at: now
                    )
                    state.watchRequest = command
                    return persist(PendingSave(
                        changes: mutation.changes.map {
                            TimerChange(timer: $0.timer, endedAt: $0.endedAt)
                        }, collection: mutation.collection,
                        dismissedTimerID: command.operation == .deleteTimer
                            ? command.targetID : nil,
                        clearsTimerDraft: command.operation == .startTimer
                            && state.isEditorPresented
                    ), state: &state)
                } catch {
                    return .send(.delegate(WatchExperimentResponse(
                        requestID: command.requestID, phase: .failed,
                        error: (error as? WatchExperimentError) ?? .invalidState
                    )))
                }

            case .delegate:
                return .none

            case let .configure(mode, timerSeconds, timers):
                guard !state.isConfigured else { return .none }
                state.mode = mode
                state.timerSeconds = timerSeconds
                state.timerCollection = ExperimentTimerCollection(timers: timers, currentTime: now)
                state.isConfigured = true
                return .send(.timerTick(now))

            case .editorPresented, .draftSecondsChanged:
                return editTimerDraft(action, state: &state)

            case let .timerTabSelected(tab):
                state.selectedTimerTab = tab
                return .none

            case let .timerStarted(index):
                guard state.canModifyTimers,
                      state.timerSeconds.indices.contains(index) else { return .none }
                return startTimer(seconds: state.timerSeconds[index], state: &state)

            case let .customTimerStarted(seconds):
                guard state.canModifyTimers else { return .none }
                let effect = startTimer(seconds: seconds, state: &state)
                state.pendingSave?.clearsTimerDraft = true
                return effect

            case let .timerPaused(id):
                guard state.canModifyTimers else { return .none }
                var collection = state.timerCollection
                guard collection.pause(id: id, at: now) else { return .none }
                return saveChanges(from: state.timerCollection, to: collection, state: &state)

            case .allTimersPaused:
                guard state.canModifyTimers, state.timerCollection.hasRunningTimers else {
                    return .none
                }
                var collection = state.timerCollection
                let runningIDs = collection.timers.filter { $0.status == .running }.map(\.id)
                let pausedAt = now
                for id in runningIDs {
                    collection.pause(id: id, at: pausedAt)
                }
                return saveChanges(from: state.timerCollection, to: collection, state: &state)

            case let .timerResumed(id):
                guard state.canModifyTimers else { return .none }
                var collection = state.timerCollection
                guard collection.resume(id: id, at: now) else { return .none }
                return saveChanges(from: state.timerCollection, to: collection, state: &state)

            case let .timerDeleted(id):
                guard state.canModifyTimers,
                      let timer = state.timerCollection.timers.first(where: { $0.id == id }) else {
                    return .none
                }
                var collection = state.timerCollection
                guard collection.delete(id: id) else { return .none }
                return persist(
                    PendingSave(
                        changes: [TimerChange(timer: timer, endedAt: now)],
                        collection: collection,
                        dismissedTimerID: id
                    ),
                    state: &state
                )

            case let .timerTick(date):
                guard state.canModifyTimers else { return .none }
                let previous = state.timerCollection
                state.timerCollection.advance(to: date)
                let finished = state.timerCollection.timers.filter { timer in
                    timer.status == .finished
                        && previous.timers.first { $0.id == timer.id }?.status != .finished
                }
                if !finished.isEmpty {
                    return persist(
                        PendingSave(
                            changes: finished.map { TimerChange(timer: $0, endedAt: nil) },
                            collection: state.timerCollection
                        ),
                        state: &state
                    )
                }
                return state.timerCollection.hasRunningTimers ? tickerEffect : .none

            case .timerSaved:
                guard let pendingSave = state.pendingSave else { return .none }
                state.timerCollection = pendingSave.collection
                if pendingSave.clearsTimerDraft {
                    state.initialDraftSeconds = state.draftSeconds
                    state.isEditorPresented = false
                }
                state.pendingSave = nil
                state.isSaving = false
                state.saveFailed = false
                state.selectedTimerTab = .active
                let command = state.watchRequest
                state.watchRequest = nil
                if let command {
                    return .concatenate(
                        .send(.delegate(WatchExperimentResponse(
                            requestID: command.requestID, phase: .completed
                        ))),
                        .send(.timerTick(now))
                    )
                }
                return .send(.timerTick(now))

            case .timerSaveFailed:
                state.isSaving = false
                state.saveFailed = true
                if let command = state.watchRequest {
                    return .send(.delegate(WatchExperimentResponse(
                        requestID: command.requestID, phase: .failed, error: .storageFailed
                    )))
                }
                return .none

            case .retrySaveTapped:
                guard let pendingSave = state.pendingSave, !state.isSaving else { return .none }
                return persist(pendingSave, state: &state)
            }
        }
    }

}

private extension SessionTimerFeature {
    func startTimer(seconds: Int, state: inout State) -> Effect<Action> {
        var collection = state.timerCollection
        guard collection.start(id: uuid(), durationSeconds: seconds, at: now) else { return .none }
        return saveChanges(from: state.timerCollection, to: collection, state: &state)
    }

    private func saveChanges(
        from previous: ExperimentTimerCollection,
        to collection: ExperimentTimerCollection,
        state: inout State
    ) -> Effect<Action> {
        let changes = collection.timers.compactMap { timer -> TimerChange? in
            let old = previous.timers.first { $0.id == timer.id }
            return old == timer ? nil : TimerChange(timer: timer, endedAt: nil)
        }
        guard !changes.isEmpty else { return .none }
        return persist(PendingSave(changes: changes, collection: collection), state: &state)
    }

    private func persist(_ pendingSave: PendingSave, state: inout State) -> Effect<Action> {
        state.pendingSave = pendingSave
        state.isSaving = true
        state.saveFailed = false
        let experimentID = state.experimentID
        return .concatenate(
            .cancel(id: CancelID.timerTick),
            .run { send in
                do {
                    if let timerID = pendingSave.dismissedTimerID,
                       let change = pendingSave.changes.first(where: {
                           $0.timer.id == timerID
                       }), let endedAt = change.endedAt {
                        try await experimentClient.beginTimerDeletion(
                            experimentID, timerID, change.timer.finishedAt ?? endedAt
                        )
                    }
                    for change in pendingSave.changes {
                        try await experimentClient.saveTimer(
                            experimentID,
                            change.timer,
                            change.endedAt
                        )
                    }
                    if let timerID = pendingSave.dismissedTimerID {
                        try await experimentClient.dismissWatchTimer(
                            experimentID: experimentID, timerID: timerID
                        )
                    }
                    await send(.timerSaved)
                } catch {
                    await send(.timerSaveFailed)
                }
            }
        )
    }
}

private extension SessionTimerFeature {
    var tickerEffect: Effect<Action> {
        .run { send in
            try await Task.sleep(for: .seconds(1))
            await send(.timerTick(.now))
        }
        .cancellable(id: CancelID.timerTick, cancelInFlight: true)
    }

}

extension SessionTimerFeature.State {
    var canModifyTimers: Bool {
        !isClosing && pendingSave == nil && !isSaving
    }

}
