import SwiftUI

public struct TimerTabItem: View {
    private let title: String
    private let isSelected: Bool
    private let action: () -> Void
    private let style: TimerTabs.Style
    private let layout = LayoutTokens()

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
                    .labcord(foregroundToken)
                )
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, style == .pill ? layout.spacing8 : layout.spacing16)
                .frame(minHeight: style == .plain ? 54 : nil)
                .background {
                    if style == .pill && isSelected {
                        Capsule().fill(.labcord(.fillSelected))
                    }
                }
                .labcordMotion(.state, value: isSelected)
                .contentShape(Rectangle())
        }
        .buttonStyle(LabcordPlainButtonStyle())
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foregroundToken: ColorToken {
        style == .pill ? .labelBrand : (isSelected ? .labelPrimary : .labelTertiary)
    }

    private var horizontalPadding: CGFloat {
        style == .pill ? (isSelected ? layout.spacing16 : layout.spacing12) : layout.spacing8
    }
}

#if DEBUG
#Preview("타이머 탭 · 기본·선택") {
    _ = FontRegistration.register()
    return HStack(spacing: 12) {
        TimerTabItem(title: "세팅된 타이머", isSelected: true) { }
        TimerTabItem(title: "진행중인 타이머", isSelected: false) { }
    }
    .background(.labcord(.backgroundPrimary))
    .labcordTheme(LabcordTheme(context: .experiment))
}
#endif
