import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct VideoLiveActivityView: View {
    let store: StoreOf<VideoFeature>
    let availableWidth: CGFloat

    @State private var isExpanded = false

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
                        elapsed: String(format: "00:%02d", Int(elapsed)),
                        progress: elapsed / Double(VideoRecordingSettings.durationSeconds)
                    ),
                    onStop: { store.send(.stopRequested) },
                    onRetry: { store.send(.recordRequested) }
                )
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            isExpanded = true
        }
    }

    private func elapsedSeconds(at date: Date) -> Double {
        guard case let .recording(startedAt) = store.phase else { return 0 }
        return min(
            Double(VideoRecordingSettings.durationSeconds),
            max(0, date.timeIntervalSince(startedAt))
        )
    }
}
