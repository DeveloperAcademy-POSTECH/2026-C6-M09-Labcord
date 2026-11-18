import ComposableArchitecture
import LabcordiOS
import LabcordShared

extension AppFeature {
    func handleLaunch(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case .appeared:
            if !state.hasCompletedOnboarding {
                state.onboarding = OnboardingFeature.State()
            }
            guard !state.hasRequestedLaunchPermissions else { return .none }
            state.hasRequestedLaunchPermissions = true
            return .run { _ in
                _ = await microphonePermissionClient.requestAccess()
                guard !Task.isCancelled else { return }
                _ = await cameraPermissionClient.requestAccess()
                guard !Task.isCancelled else { return }
                _ = await speechRecognitionPermissionClient.requestAccess()
                guard !Task.isCancelled else { return }
                _ = try? await notificationPermissionClient.requestAccess()
            }

        case .onboarding(.delegate(.finished)):
            state.onboarding = nil
            state.$hasCompletedOnboarding.withLock { $0 = true }
            if state.home.isFirstHome {
                state.home.$requiresGesturePractice.withLock { $0 = true }
            }

        default:
            break
        }
        return .none
    }
}
