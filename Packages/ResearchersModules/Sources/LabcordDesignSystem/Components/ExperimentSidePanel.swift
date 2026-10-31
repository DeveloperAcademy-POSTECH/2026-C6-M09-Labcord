import SwiftUI

public struct ExperimentSidePanel<Content: View>: View {
    public enum Layout: String, CaseIterable, Sendable {
        case portrait
        case landscape
    }

    @Binding private var isExpanded: Bool

    private let layout: Layout
    private let content: () -> Content

    @Environment(\.labcordTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scaledIconSize: CGFloat = 28

    public init(
        layout: Layout = .landscape,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.layout = layout
        _isExpanded = isExpanded
        self.content = content
    }

    public var body: some View {
        arrangedContent
            .frame(
                maxWidth: usesIntrinsicAccessibilitySize ? nil : .infinity,
                maxHeight: usesIntrinsicAccessibilitySize ? nil : .infinity,
                alignment: .bottomTrailing
            )
            .labcordMotion(.layout, value: isExpanded)
            .compositingGroup()
            .shadow(
                color: shadowColor,
                radius: theme.effects(for: colorScheme).shadowSoftRadius / 2,
                x: 0,
                y: theme.effects(for: colorScheme).shadowSoftOffsetY
            )
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var arrangedContent: some View {
        switch layout {
        case .portrait:
            VStack(spacing: 0) {
                handle
                portraitBody
            }
            .fixedSize(
                horizontal: usesIntrinsicAccessibilitySize,
                vertical: usesIntrinsicAccessibilitySize
            )
            .frame(
                minWidth: usesIntrinsicAccessibilitySize ? 402 : nil,
                idealWidth: usesIntrinsicAccessibilitySize ? nil : 402,
                maxWidth: usesIntrinsicAccessibilitySize ? nil : .infinity
            )
        case .landscape:
            HStack(spacing: 0) {
                handle
                landscapeBody
            }
            .fixedSize(
                horizontal: usesIntrinsicAccessibilitySize,
                vertical: usesIntrinsicAccessibilitySize
            )
            .frame(
                minWidth: usesIntrinsicAccessibilitySize ? landscapeWidth : nil,
                idealWidth: usesIntrinsicAccessibilitySize ? nil : landscapeWidth,
                maxWidth: usesIntrinsicAccessibilitySize ? nil : landscapeWidth
            )
        }
    }

    private var handle: some View {
        Button(action: toggle) {
            handleLabel
                .background(.labcord(.fillDark), in: panelShape)
                .contentShape(panelShape)
        }
        .buttonStyle(LabcordPlainButtonStyle())
        .padding(layout == .portrait ? .vertical : .horizontal, handleHitInset)
        .contentShape(Rectangle())
        .padding(layout == .portrait ? .vertical : .horizontal, -handleHitInset)
        .accessibilityLabel(Text(isExpanded ? "실험 패널 접기" : "실험 패널 펼치기"))
        .accessibilityValue(Text(isExpanded ? "펼쳐짐" : "접힘"))
    }

    @ViewBuilder
    private var handleLabel: some View {
        switch layout {
        case .portrait:
            handleIcon
                .padding(.top, theme.layout.spacing4)
                .padding(.horizontal, theme.layout.spacing8)
                .frame(width: handleLength)
        case .landscape:
            handleIcon
                .padding(.leading, theme.layout.spacing4)
                .padding(.vertical, theme.layout.spacing8)
                .frame(height: handleLength)
        }
    }

    private var handleIcon: some View {
        LabcordIconArtwork(
            icon: layout == .portrait ? .caretDown : .caretRight,
            size: 28,
            relativeTo: .body
        )
        .foregroundStyle(.labcord(.labelBrand))
        .rotationEffect(.degrees(layout == .landscape && !isExpanded ? 180 : 0))
    }

    private var portraitBody: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: isExpanded ? nil : 51)

            if isExpanded {
                content()
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 315,
                        maxHeight: .infinity,
                        alignment: .bottom
                    )
                    .padding(.top, theme.layout.spacing12)
                    .padding(.horizontal, theme.layout.spacing16)
                    .padding(.bottom, theme.layout.spacing32)
                    .frame(minHeight: 366)
                    .transition(contentTransition(edge: .bottom))
            }
        }
        .background(.labcord(.fillDark), in: panelShape)
        .clipShape(panelShape)
    }

    private var landscapeBody: some View {
        ZStack(alignment: .trailing) {
            Color.clear
                .frame(width: isExpanded ? nil : 62, height: 402)

            if isExpanded {
                content()
                    .frame(maxWidth: .infinity, minHeight: 322)
                    .padding(.leading, theme.layout.spacing16)
                    .padding(.trailing, 62)
                    .padding(.top, 80)
                    .frame(maxWidth: .infinity, minHeight: 402)
                    .transition(contentTransition(edge: .trailing))
            }
        }
        .background(.labcord(.fillDark), in: panelShape)
        .clipShape(panelShape)
    }

    private func contentTransition(edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge)
    }

    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: theme.layout.radiusLg,
            bottomLeadingRadius: layout == .landscape ? theme.layout.radiusLg : 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: layout == .portrait ? theme.layout.radiusLg : 0
        )
    }

    private var handleLength: CGFloat {
        max(83, scaledIconSize + theme.layout.spacing16)
    }

    private var handleHitInset: CGFloat {
        max(0, (44 - scaledIconSize - theme.layout.spacing4) / 2)
    }

    private var usesIntrinsicAccessibilitySize: Bool {
        dynamicTypeSize.isAccessibilitySize && isExpanded
    }

    private var landscapeWidth: CGFloat {
        isExpanded ? 400 : 62 + scaledIconSize + theme.layout.spacing4
    }

    private var shadowColor: Color {
        theme.color(.effectShadowSoftColor, colorScheme: colorScheme)
    }

    private func toggle() {
        guard isEnabled else { return }
        withAnimation(reduceMotion ? nil : LabcordMotion.layout.animation) {
            isExpanded.toggle()
        }
    }
}

public extension ExperimentSidePanel where Content == EmptyView {
    init(layout: Layout = .landscape, isExpanded: Binding<Bool>) {
        self.init(layout: layout, isExpanded: isExpanded, content: EmptyView.init)
    }
}

#Preview("실험 패널 · 가로") {
    @Previewable @State var isExpanded = true

    ExperimentSidePanel(layout: .landscape, isExpanded: $isExpanded) {
        Text("실험 도구")
            .foregroundStyle(.white)
    }
    .frame(width: 450, height: 430)
    .background(.labcord(.backgroundPrimary))
    .labcordTheme(LabcordTheme(context: .experiment))
}

#Preview("실험 패널 · 세로") {
    @Previewable @State var isExpanded = false

    ExperimentSidePanel(layout: .portrait, isExpanded: $isExpanded) {
        Text("실험 도구")
            .foregroundStyle(.white)
    }
    .frame(width: 402, height: 430)
    .background(.labcord(.backgroundPrimary))
    .labcordTheme(LabcordTheme(context: .experiment))
}
