import SwiftUI

/// A compact capsule that expands into the supplied Live Activity content.
/// The caller owns visibility and placement, including device-specific geometry.
public struct AnimatedLiveActivityContainer<Content: View>: View {
    private let isExpanded: Bool
    private let collapsedSize: CGSize
    private let expandedWidth: CGFloat
    private let minimumContentHeight: CGFloat
    private let maximumContentHeight: CGFloat?
    private let animatesContentHeight: Bool
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedHeight: CGFloat = 138

    public init(
        isExpanded: Bool,
        collapsedSize: CGSize,
        expandedWidth: CGFloat,
        minimumContentHeight: CGFloat = 106,
        maximumContentHeight: CGFloat? = nil,
        animatesContentHeight: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.isExpanded = isExpanded
        self.collapsedSize = collapsedSize
        self.expandedWidth = expandedWidth
        self.minimumContentHeight = minimumContentHeight
        self.maximumContentHeight = maximumContentHeight
        self.animatesContentHeight = animatesContentHeight
        self.content = content()
    }

    public var body: some View {
        ZStack {
            Color(.General.Fill.liveActivity)

            LiveActivityContainer(
                minimumContentHeight: minimumContentHeight,
                maximumContentHeight: maximumContentHeight
            ) { content }
                .frame(width: expandedWidth)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ExpandedHeightKey.self, value: geometry.size.height
                        )
                    }
                }
                .opacity(isExpanded ? 1 : 0)
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
        }
        .frame(
            width: isExpanded ? expandedWidth : collapsedSize.width,
            height: isExpanded ? expandedHeight : collapsedSize.height
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: isExpanded ? 44 : collapsedSize.height / 2,
                style: isExpanded ? .continuous : .circular
            )
        )
        .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.08), value: isExpanded)
        .onPreferenceChange(ExpandedHeightKey.self) { height in
            guard height > 0, abs(expandedHeight - height) > 0.5 else { return }
            if animatesContentHeight && !reduceMotion {
                withAnimation(.easeOut(duration: 0.25)) {
                    expandedHeight = height
                }
            } else {
                expandedHeight = height
            }
        }
    }
}

private struct ExpandedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview("Animated Live Activity") {
    AnimatedLiveActivityContainer(
        isExpanded: true, collapsedSize: CGSize(width: 126, height: 37), expandedWidth: 350
    ) {
        Text("기록 중").foregroundStyle(.white)
    }
}
