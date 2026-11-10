import SwiftUI

public struct TimerTabItem: View {
    private let title: String
    private let isSelected: Bool
    private let action: () -> Void
    private let style: TimerTabs.Style
    private let appearance: TimerTabs.Appearance

    public init(
        title: String,
        isSelected: Bool,
        appearance: TimerTabs.Appearance = .experiment,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            isSelected: isSelected,
            style: .plain,
            appearance: appearance,
            action: action
        )
    }

    init(
        title: String,
        isSelected: Bool,
        style: TimerTabs.Style,
        appearance: TimerTabs.Appearance,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.style = style
        self.appearance = appearance
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .typography(isSelected ? Typography.bodySemiBold : Typography.body)
                .transaction { $0.animation = nil }
                .foregroundStyle(
                    foregroundColor
                )
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, horizontalPadding)
                .padding(
                    .vertical,
                    style == .pill ? LayoutTokens.spacing8 : LayoutTokens.spacing12
                )
                .frame(minHeight: style == .plain ? 46 : nil)
                .background {
                    if style == .pill && isSelected {
                        Capsule().fill(selectedBackgroundColor)
                    }
                }
                .labcordMotion(.state, value: isSelected)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackButtonStyle())
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foregroundColor: Color {
        switch (appearance, style, isSelected) {
        case (.general, .pill, true): Color(.General.Label.brand)
        case (.general, .pill, false): Color(.General.Label.quaternary)
        case (.general, .plain, true): Color(.General.Label.primary)
        case (.general, .plain, false): Color(.General.Label.tertiary)
        case (.experiment, .pill, true): Color(.Experiment.Label.brand)
        case (.experiment, .pill, false): Color(.Experiment.Label.quaternary)
        case (.experiment, .plain, true): Color(.Experiment.Label.primary)
        case (.experiment, .plain, false): Color(.Experiment.Label.tertiary)
        }
    }

    private var selectedBackgroundColor: Color {
        switch appearance {
        case .general: Color(.General.Fill.selected)
        case .experiment: Color(.Experiment.Fill.selected)
        }
    }

    private var horizontalPadding: CGFloat {
        style == .pill
            ? (isSelected ? LayoutTokens.spacing16 : LayoutTokens.spacing12)
            : LayoutTokens.spacing4
    }
}

#Preview("타이머 탭 · 기본·선택") {
    _ = FontRegistration.register()
    return HStack(spacing: 12) {
        TimerTabItem(title: "세팅된 타이머", isSelected: true) { }
        TimerTabItem(title: "진행중인 타이머", isSelected: false) { }
    }
    .background(Color(.Experiment.Background.primary))
}
