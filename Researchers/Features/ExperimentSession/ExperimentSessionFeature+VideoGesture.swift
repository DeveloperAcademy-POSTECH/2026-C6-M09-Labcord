import ComposableArchitecture
import Foundation

extension ExperimentSessionFeature {
    func handleVideoGesture(_ detectedAt: Date, state: State) -> Effect<Action> {
        guard !state.capture.isPhotoCaptureScheduled, !state.capture.isCapturingPhoto,
              detectedAt.timeIntervalSinceNow > -0.5 else { return .none }
        switch state.capture.videoPhase {
        case .idle: return .send(.videoStartRequested)
        case .starting, .recording: return .send(.capture(.video(.stopRequested)))
        case .preview: return .none
        }
    }
}
