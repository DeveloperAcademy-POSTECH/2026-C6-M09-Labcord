import SwiftUI

public enum LabcordAccordionState: String, Sendable {
    case `default`
    case disabled
}

public struct LabcordAccordion<Content: View>: View {
    @Binding private var isExpanded: Bool

    private let title: String
    private let count: String
    private let showsCount: Bool
    private let state: LabcordAccordionState
    private let content: () -> Content

    private let tokenLayout = LayoutTokens()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ title: String,
        count: Int? = nil,
        showsCount: Bool = true,
        isExpanded: Binding<Bool>,
        state: LabcordAccordionState = .default,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            count: count.map { String($0) } ?? "",
            showsCount: showsCount,
            isExpanded: isExpanded,
            state: state,
            content: content
        )
    }

    public init(
        title: String = "샘플·분석 대상",
        count: String = "4",
        showsCount: Bool = true,
        isExpanded: Binding<Bool>,
        state: LabcordAccordionState = .default,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.count = count
        self.showsCount = showsCount
        _isExpanded = isExpanded
        self.state = state
        self.content = content
    }

    public var body: some View {
        VStack(
            alignment: .leading,
            spacing: isOpen ? tokenLayout.spacing16 : tokenLayout.spacing12
        ) {
            Button(action: toggle) {
                HStack(spacing: tokenLayout.spacing12) {
                    HStack(spacing: tokenLayout.spacing12) {
                        Text(title)
                            .typography(Typography.callout)
                            .foregroundStyle(foregroundColor)
                            .fixedSize(horizontal: false, vertical: true)

                        if hasCount {
                            Text(count)
                                .typography(Typography.subheadline)
                                .foregroundStyle(countColor)
                                .contentTransition(.numericText())
                                .labcordMotion(.state, value: count)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .labcordMotion(.state, value: hasCount)

                    LabcordIconArtwork(
                        icon: .caretDown,
                        size: 20,
                        relativeTo: .callout
                    )
                    .foregroundStyle(countColor)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state == .disabled)

            if isOpen {
                content()
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                    .transition(.opacity)
            }
        }
        .animation(expansionAnimation, value: isOpen)
        .padding(tokenLayout.spacing16)
        .padding(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            backgroundColor,
            in: RoundedRectangle(cornerRadius: tokenLayout.radiusSm)
        )
        .overlay {
            RoundedRectangle(cornerRadius: tokenLayout.radiusSm)
                .strokeBorder(Color("General/Border/Default", bundle: .module), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var isOpen: Bool {
        state == .default && isExpanded
    }

    private var expansionAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.2)
    }

    private var hasCount: Bool {
        showsCount && !count.isEmpty && count != "0"
    }

    private var foregroundColor: Color {
        state == .disabled
            ? Color("General/Label/Disabled", bundle: .module)
            : Color("General/Label/Primary", bundle: .module)
    }

    private var countColor: Color {
        state == .disabled
            ? Color("General/Label/Disabled", bundle: .module)
            : Color("General/Label/Secondary", bundle: .module)
    }

    private var backgroundColor: Color {
        state == .disabled
            ? Color("General/Fill/Secondary", bundle: .module)
            : Color("General/Background/Grouped/Secondary", bundle: .module)
    }

    private func toggle() {
        guard state == .default else { return }
        withAnimation(expansionAnimation) {
            isExpanded.toggle()
        }
    }
}

#if DEBUG
private struct AccordionPreviewContent: View {
    @State private var isExpanded = true

    var body: some View {
        LabcordAccordion(isExpanded: $isExpanded) {
            Text("콘텐츠 슬롯")
                .typography(Typography.subheadline)
                .foregroundStyle(Color("General/Label/Secondary", bundle: .module))
        }
    }
}

private struct DisabledAccordionPreviewContent: View {
    var body: some View {
        LabcordAccordion(
            title: "비활성 항목",
            isExpanded: .constant(false),
            state: .disabled
        ) {
            Text("표시되지 않는 콘텐츠")
        }
    }
}

#Preview("아코디언 · 기본") {
    _ = FontRegistration.register()
    return AccordionPreviewContent()
        .frame(width: 370)
        .padding()
}

#Preview("아코디언 · 큰 글자") {
    _ = FontRegistration.register()
    return AccordionPreviewContent()
        .environment(\.dynamicTypeSize, .accessibility3)
        .frame(width: 370)
        .padding()
}

#Preview("아코디언 · 비활성") {
    _ = FontRegistration.register()
    return DisabledAccordionPreviewContent()
        .frame(width: 370)
        .padding()
}
#endif
