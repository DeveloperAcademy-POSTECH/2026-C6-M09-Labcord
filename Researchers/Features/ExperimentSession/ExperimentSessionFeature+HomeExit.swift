import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

extension ExperimentSessionFeature {
    func saveHomeExit(state: inout State, at exitedAt: Date) -> Effect<Action> {
        guard let exitID = state.exitID else { return .send(.homeExitFailed) }
        let experimentID = state.experimentID
        let ownerID = state.capture.camera.ownerID
        let title = state.detail?.title ?? "실험"
        let runningTimers = state.timer.timerCollection.timers.filter {
            $0.status == .running && $0.remainingSeconds(at: exitedAt) > 0
        }
        return .run { send in
            do {
                try await experimentClient.leaveSession(experimentID, exitID, exitedAt)
            } catch {
                await send(.homeExitFailed)
                return
            }
            if !runningTimers.isEmpty,
               let status = try? await notificationPermissionClient.requestAccess() {
                switch status {
                case .authorized, .provisional, .ephemeral:
                    for timer in runningTimers {
                        try? await timerCompletionNotificationClient.schedule(
                            experimentID, title, timer
                        )
                    }
                case .notDetermined, .denied, .unknown:
                    break
                }
            }
            await cameraSessionClient.deactivate(ownerID)
            await send(.homeExitCompleted)
        }
    }
}
