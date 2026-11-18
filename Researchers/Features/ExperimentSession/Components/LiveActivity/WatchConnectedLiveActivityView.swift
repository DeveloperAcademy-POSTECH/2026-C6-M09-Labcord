import Foundation
import LabcordDesignSystem
import SwiftUI

struct WatchConnectedActivityOverlay: ViewModifier {
    let noticeID: UUID?
    let onDismiss: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if let noticeID {
                    GeometryReader { geometry in
                        WatchConnectedLiveActivityView(availableWidth: geometry.size.width) {
                            onDismiss(noticeID)
                        }
                        .id(noticeID)
                        .padding(.top, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .ignoresSafeArea(.container, edges: .top)
                    .transition(.opacity)
                }
            }
            .animation(
                reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.08),
                value: noticeID
            )
    }
}

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
                state: .watchConnected(message: "Apple Watch로도 기록할 수 있어요.", detail: "연결이 끊기면 iPhone으로만 기록할 수 있어요."),
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
