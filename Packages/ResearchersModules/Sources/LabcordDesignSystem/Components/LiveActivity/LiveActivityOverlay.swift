import SwiftUI

/// Measured capsule geometry in points, relative to the top of the app window.
public struct LiveActivityPlacement: Sendable {
    /// Placement confirmed on iPhone 18 Pro Max (iPhone19,7), in portrait.
    public static let iPhone18ProMax = LiveActivityPlacement(
        top: 12, collapsedSize: CGSize(width: 113, height: 40), expandedWidth: 327
    )

    public let top: CGFloat
    public let horizontalOffset: CGFloat
    public let collapsedSize: CGSize
    public let expandedWidth: CGFloat

    public init(
        top: CGFloat,
        horizontalOffset: CGFloat = 0,
        collapsedSize: CGSize,
        expandedWidth: CGFloat
    ) {
        self.top = top
        self.horizontalOffset = horizontalOffset
        self.collapsedSize = collapsedSize
        self.expandedWidth = expandedWidth
    }
}

public extension View {
    /// Attach to a full-window view. Unknown placements and landscape windows are hidden.
    func liveActivityOverlay<Content: View>(
        placement: LiveActivityPlacement?,
        isPresented: Bool,
        isExpanded: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        overlay(alignment: .top) {
            GeometryReader { geometry in
                if let placement, isPresented, geometry.size.height > geometry.size.width {
                    AnimatedLiveActivityContainer(
                        isExpanded: isExpanded,
                        collapsedSize: placement.collapsedSize,
                        expandedWidth: min(placement.expandedWidth, geometry.size.width)
                    ) {
                        content()
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .offset(x: placement.horizontalOffset)
                    .padding(.top, placement.top)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
    }
}
