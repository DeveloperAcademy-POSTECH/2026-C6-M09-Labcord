import SwiftUI

/// Measured capsule geometry in points, relative to the top of the app window.
public struct LiveActivityPlacement: Sendable {
    /// Portrait geometry from https://safearea.info/, subject to device verification.
    public static func forDevice(identifier: String) -> LiveActivityPlacement? {
        let top: CGFloat
        let width: CGFloat
        switch identifier {
        case "iPhone15,2", "iPhone15,4", "iPhone16,1", "iPhone17,3":
            top = 11.33
            width = 125
        case "iPhone15,3", "iPhone15,5", "iPhone16,2", "iPhone17,4":
            top = 11.33
            width = 125.33
        case "iPhone17,1", "iPhone17,2", "iPhone18,1", "iPhone18,2", "iPhone18,3":
            top = 14
            width = 125.33
        case "iPhone18,4":
            top = 20
            width = 125.33
        case "iPhone19,2", "iPhone19,3", "iPhone19,7":
            top = 14
            width = 94.67
        default:
            return nil
        }
        return LiveActivityPlacement(
            top: top, collapsedSize: CGSize(width: width, height: 36.67),
            expandedWidth: 370, expandedHorizontalInset: 16
        )
    }

    public let top: CGFloat
    public let horizontalOffset: CGFloat
    public let collapsedSize: CGSize
    public let expandedWidth: CGFloat
    public let expandedHorizontalInset: CGFloat?

    public init(
        top: CGFloat,
        horizontalOffset: CGFloat = 0,
        collapsedSize: CGSize,
        expandedWidth: CGFloat,
        expandedHorizontalInset: CGFloat? = nil
    ) {
        self.top = top
        self.horizontalOffset = horizontalOffset
        self.collapsedSize = collapsedSize
        self.expandedWidth = expandedWidth
        self.expandedHorizontalInset = expandedHorizontalInset
    }
}

public extension View {
    /// Attach to a full-window view. Unknown placements and landscape windows are hidden.
    func liveActivityOverlay<Content: View>(
        placement: LiveActivityPlacement?,
        isPresented: Bool,
        isExpanded: Bool,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        overlay(alignment: .top) {
            GeometryReader { geometry in
                if let placement, isPresented, geometry.size.height > geometry.size.width {
                    if let onDismiss {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onDismiss)
                            .accessibilityHidden(true)
                    }
                    AnimatedLiveActivityContainer(
                        isExpanded: isExpanded,
                        collapsedSize: placement.collapsedSize,
                        expandedWidth: placement.expandedHorizontalInset.map {
                            max(0, geometry.size.width - 2 * $0)
                        } ?? min(placement.expandedWidth, geometry.size.width)
                    ) {
                        content()
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .offset(x: placement.horizontalOffset)
                    .padding(.top, placement.top)
                    .accessibilityAction(.escape) { onDismiss?() }
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
    }
}
