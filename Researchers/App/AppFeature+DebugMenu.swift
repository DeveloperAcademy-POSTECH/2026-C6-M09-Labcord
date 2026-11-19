#if DEBUG
import ComposableArchitecture
import Foundation
import LabcordiOS

extension AppFeature {
    @ObservableState
    struct DebugMenuState: Equatable {
        @Shared(.appStorage("includesRecordingDemo")) var includesDemo = false
        var didReconcileBundle = false
        var isPresented = false
        var isWorking = false
        var didReset = false
        var errorMessage: String?
    }

    enum DebugMenuAction {
        case open
        case close
        case setDemo(Bool)
        case reset
        case demoInstalled(String?)
        case resetFinished(didReset: Bool, error: String?)
    }

    var debugMenuReducer: some Reducer<State, Action> {
        Reduce { state, action in
            if case .appeared = action {
                return reconcileDemoBundle(&state.debugMenu)
            }
            guard case let .debugMenu(action) = action else { return .none }
            switch action {
            case .open:
                guard !state.debugMenu.isPresented else { return .none }
                state.debugMenu.isPresented = true
                return .none

            case .close:
                guard !state.debugMenu.isWorking else { return .none }
                state.debugMenu.isPresented = false
                if state.debugMenu.didReset {
                    resetNavigation(&state)
                    return .send(.home(.list(.cancelLoad)))
                }
                if state.watchPendingStartID != nil {
                    return openWatchSession(&state)
                }
                return openReadyLiveActivityExperiment(&state)

            case let .setDemo(enabled):
                return changeDemoVisibility(enabled, state: &state)

            case let .demoInstalled(error):
                state.debugMenu.isWorking = false
                state.debugMenu.errorMessage = error
                if error == nil {
                    state.debugMenu.$includesDemo.withLock { $0 = true }
                }
                return .send(.home(.list(.load)))

            case .reset:
                guard canReset(state) else {
                    state.debugMenu.errorMessage = "진행 중인 기록이나 저장을 마친 뒤 다시 시도해 주세요."
                    return .none
                }
                guard beginDebugOperation(&state.debugMenu) else { return .none }
                return resetData(includesDemo: state.debugMenu.includesDemo)

            case let .resetFinished(didReset, error):
                state.debugMenu.isWorking = false
                state.debugMenu.errorMessage = error
                guard didReset else { return .send(.home(.list(.load))) }
                state.debugMenu.didReset = true
                resetPreferences(&state)
                return .send(.home(.list(.cancelLoad)))
            }
        }
    }

    private func changeDemoVisibility(_ enabled: Bool, state: inout State) -> Effect<Action> {
        guard state.debugMenu.isPresented, !state.debugMenu.isWorking,
              enabled != state.debugMenu.includesDemo else { return .none }
        guard enabled || prepareToHideDemo(&state) else {
            state.debugMenu.errorMessage = "진행 중인 데모 실험이나 기록 편집을 마친 뒤 다시 시도해 주세요."
            return .none
        }
        guard enabled else {
            state.debugMenu.errorMessage = nil
            state.debugMenu.$includesDemo.withLock { $0 = false }
            return .send(.home(.list(.load)))
        }
        guard beginDebugOperation(&state.debugMenu) else { return .none }
        return installDemo()
    }

    private func prepareToHideDemo(_ state: inout State) -> Bool {
        guard state.watchRequestID == nil, state.watchPendingStartID == nil,
              state.screenNavigation == nil else { return false }
        let hasOpenDemoSession = state.path.ids.contains { id in
            guard let session = state.path[id: id, case: \.session] else { return false }
            return RecordingDemoSeeder.owns(session.experimentID)
        }
        guard !hasOpenDemoSession else { return false }

        let demoResultID = state.path.ids.first { id in
            guard let result = state.path[id: id, case: \.result] else { return false }
            return RecordingDemoSeeder.owns(result.experimentID)
        }
        guard let demoResultID else { return true }
        guard state.path.ids.last == demoResultID,
              state.path[id: demoResultID, case: \.result]?.canRefreshExternalRecords == true
        else { return false }
        state.path.pop(from: demoResultID)
        return true
    }

    private func canReset(_ state: State) -> Bool {
        guard !state.reviewSaving, !state.home.list.isDeleting, state.watchRequestID == nil,
              state.watchPendingStartID == nil, state.screenNavigation == nil else { return false }
        guard let id = state.path.ids.last else { return true }
        if let session = state.path[id: id, case: \.session] {
            return !session.hasUnsettledScreenWork
        }
        if let result = state.path[id: id, case: \.result] {
            return !result.isRecordSaving && !result.isResuming
        }
        if let registration = state.path[id: id, case: \.registration] {
            return !registration.isSaving && !registration.importing
                && !registration.analysisStarting && registration.invalidatingJobID == nil
        }
        return true
    }

    private func beginDebugOperation(_ state: inout DebugMenuState) -> Bool {
        guard state.isPresented, !state.isWorking else { return false }
        state.isWorking = true
        state.errorMessage = nil
        return true
    }

    private func reconcileDemoBundle(_ state: inout DebugMenuState) -> Effect<Action> {
        guard state.includesDemo, RecordingDemoSeeder.hasReplacement,
              !state.didReconcileBundle, !state.isWorking
        else { return .none }
        state.didReconcileBundle = true
        state.isWorking = true
        return installDemo()
    }

    private func installDemo() -> Effect<Action> {
        .run { @MainActor send in
            do {
                try await RecordingDemoSeeder().install()
                send(.debugMenu(.demoInstalled(nil)))
            } catch {
                send(.debugMenu(.demoInstalled(error.localizedDescription)))
            }
        }
    }

    private func resetData(includesDemo: Bool) -> Effect<Action> {
        .run { @MainActor send in
            let cleanupWarning: String?
            do {
                cleanupWarning = try await DebugAppDataReset().run()
            } catch {
                send(.debugMenu(.resetFinished(
                    didReset: false, error: error.localizedDescription
                )))
                return
            }
            do {
                if includesDemo { try await RecordingDemoSeeder().install() }
                send(.debugMenu(.resetFinished(didReset: true, error: cleanupWarning)))
            } catch {
                let warning = [cleanupWarning, error.localizedDescription]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                send(.debugMenu(.resetFinished(didReset: true, error: warning)))
            }
        }
    }

    private func resetPreferences(_ state: inout State) {
        state.$hasCompletedOnboarding.withLock { $0 = false }
        state.home.$hasCompletedFirstHome.withLock { $0 = false }
        state.home.$hasShownGuide.withLock { $0 = false }
        state.home.$requiresGesturePractice.withLock { $0 = false }
    }

    private func resetNavigation(_ state: inout State) {
        let debugMenu = state.debugMenu
        let listRevision = state.home.list.loadRevision
        let watchIsActive = state.watchIsActive
        let watchSplashPhase = state.watchSplashPhase
        state = State()
        state.onboarding = OnboardingFeature.State()
        state.watchIsActive = watchIsActive
        state.watchSplashPhase = watchSplashPhase
        state.home.list.loadRevision = listRevision
        state.debugMenu = debugMenu
        state.debugMenu.didReset = false
    }
}
#endif

extension AppFeature.State {
    var isDebugMenuPresented: Bool {
        #if DEBUG
        debugMenu.isPresented
        #else
        false
        #endif
    }
}
