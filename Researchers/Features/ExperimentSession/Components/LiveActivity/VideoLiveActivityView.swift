import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct VideoLiveActivityView: View {
    let store: StoreOf<VideoFeature>
    let availableWidth: CGFloat
    let isExpanded: Bool

    var body: some View {
        AnimatedLiveActivityContainer(
            isExpanded: isExpanded,
            collapsedSize: CGSize(width: 125, height: 37),
            expandedWidth: max(0, availableWidth - 2 * LayoutTokens.spacing16),
            minimumContentHeight: 52,
            maximumContentHeight: 52
        ) {
            TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                let elapsed = elapsedSeconds(at: timeline.date)
                LiveActivityContent(
                    state: .videoRecording(
                        elapsed: String(format: "%02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60),
                        progress: min(1, elapsed / Double(VideoRecordingSettings.durationSeconds))
                    ),
                    onStop: { store.send(.stopRequested) },
                    onRetry: { store.send(.recordRequested) }
                )
            }
        }
    }

    private func elapsedSeconds(at date: Date) -> Double {
        guard case let .recording(startedAt) = store.phase else { return 0 }
        return max(0, date.timeIntervalSince(startedAt))
    }
}
