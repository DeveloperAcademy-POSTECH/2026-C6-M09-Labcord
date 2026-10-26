import ComposableArchitecture
import Foundation
import LabcordShared

@Reducer
struct ExperimentSessionFeature {
    enum TimerTab: Equatable {
        case configured
        case active
    }

    @ObservableState
    struct State: Equatable {
        var selectedTimerTab: TimerTab = .configured
        var timerSeconds: [Int] = [5400, 120, 10, 5, 120, 30, 60, 900, 2000, 2500, 3000, 150]
        var timerCollection = ExperimentTimerCollection()
    }

    enum Action: Equatable {
        case timerTabSelected(TimerTab)
        case timerStarted(Int)
        case customTimerStarted(Int)
        case timerConfigured(Int)
        case timerPaused(UUID)
        case timerResumed(UUID)
        case timerDeleted(UUID)
        case timerTick(Date)
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case timerTick
    }

    private var tickerEffect: Effect<Action> {
        .run { send in
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(1))
                await send(.timerTick(.now))
            }
        }
        .cancellable(id: CancelID.timerTick, cancelInFlight: true)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .timerTabSelected(tab):
                state.selectedTimerTab = tab
                return .none

            case let .timerStarted(index):
                guard state.timerSeconds.indices.contains(index) else { return .none }

                let wasRunning = state.timerCollection.hasRunningTimers
                guard state.timerCollection.start(
                    durationSeconds: state.timerSeconds[index],
                    at: .now
                ) else { return .none }
                return wasRunning ? .none : tickerEffect

            case let .customTimerStarted(seconds):
                let wasRunning = state.timerCollection.hasRunningTimers
                guard state.timerCollection.start(durationSeconds: seconds, at: .now) else {
                    return .none
                }
                return wasRunning ? .none : tickerEffect

            case let .timerConfigured(seconds):
                guard seconds > 0, state.timerSeconds.count < 12 else { return .none }
                state.timerSeconds.append(seconds)
                return .none

            case let .timerPaused(id):
                state.timerCollection.pause(id: id, at: .now)
                return state.timerCollection.hasRunningTimers
                    ? .none
                    : .cancel(id: CancelID.timerTick)

            case let .timerResumed(id):
                let wasRunning = state.timerCollection.hasRunningTimers
                guard state.timerCollection.resume(id: id, at: .now) else { return .none }
                return wasRunning ? .none : tickerEffect

            case let .timerDeleted(id):
                state.timerCollection.delete(id: id)
                return .none

            case let .timerTick(now):
                state.timerCollection.advance(to: now)
                return state.timerCollection.hasRunningTimers
                    ? .none
                    : .cancel(id: CancelID.timerTick)
            }
        }
    }
}
