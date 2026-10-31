import SwiftUI

public struct TimerTabItem: View {
    private let title: String
    private let isSelected: Bool
    private let action: () -> Void
    private let style: TimerTabs.Style

    public init(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.init(title: title, isSelected: isSelected, style: .plain, action: action)
    }

    init(
        title: String,
        isSelected: Bool,
        style: TimerTabs.Style,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.style = style
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
                    style == .pill ? LayoutTokens.spacing8 : LayoutTokens.spacing16
                )
                .frame(minHeight: style == .plain ? 54 : nil)
                .background {
                    if style == .pill && isSelected {
                        Capsule().fill(Color("Experiment/Fill/Selected", bundle: .module))
                    }
                }
                .labcordMotion(.state, value: isSelected)
                .contentShape(Rectangle())
        }
        .buttonStyle(LabcordPlainButtonStyle())
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foregroundColor: Color {
        style == .pill ? Color("Experiment/Label/Brand", bundle: .module)
            : (isSelected ? Color("Experiment/Label/Primary", bundle: .module)
                : Color("Experiment/Label/Tertiary", bundle: .module))
    }

    private var horizontalPadding: CGFloat {
        style == .pill
            ? (isSelected ? LayoutTokens.spacing16 : LayoutTokens.spacing12)
            : LayoutTokens.spacing8
    }
}

#Preview("타이머 탭 · 기본·선택") {
    _ = FontRegistration.register()
    return HStack(spacing: 12) {
        TimerTabItem(title: "세팅된 타이머", isSelected: true) { }
        TimerTabItem(title: "진행중인 타이머", isSelected: false) { }
    }
    .background(Color("Experiment/Background/Primary", bundle: .module))
}
