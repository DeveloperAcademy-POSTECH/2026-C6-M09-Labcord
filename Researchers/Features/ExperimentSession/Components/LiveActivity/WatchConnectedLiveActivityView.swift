import LabcordDesignSystem
import SwiftUI

struct WatchConnectedLiveActivityView: View {
    let availableWidth: CGFloat
    let onDismiss: () -> Void

    private static let height: CGFloat = 99

    @State private var isExpanded = false

    var body: some View {
        AnimatedLiveActivityContainer(
            isExpanded: isExpanded,
            collapsedSize: CGSize(width: 125, height: 37),
            expandedWidth: max(0, availableWidth - 2 * LayoutTokens.spacing16),
            minimumContentHeight: contentHeight,
            maximumContentHeight: contentHeight
        ) {
            LiveActivityContent(
                state: .watchConnected(message: "Apple Watch", detail: "기록할 준비가 됐어요."),
                onStop: {},
                onRetry: {}
            )
        }
        .task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            isExpanded = true
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }

    private var contentHeight: CGFloat {
        Self.height - 2 * LayoutTokens.spacing16
    }
}
