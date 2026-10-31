import SwiftUI

public enum DropdownState: String, Sendable {
    case `default`
    case filled
    case open
    case disabled
    case error
}

public struct DropdownTriggerLabel: View {
    private let value: String
    private let size: ComponentSize?
    private let state: DropdownState
    private let isPresented: Bool

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled
    private let layout = LayoutTokens()

    public init(
        value: String,
        size: ComponentSize? = nil,
        state: DropdownState = .default,
        isPresented: Bool = false
    ) {
        self.value = value
        self.size = size
        self.state = state
        self.isPresented = isPresented
    }

    public var body: some View {
        HStack(spacing: layout.spacing8) {
            Text(value)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            LabcordIconArtwork(
                icon: .caretDown,
                size: 16,
                relativeTo: fontTextStyle
            )
        }
        .typography(textStyle)
        .foregroundStyle((foregroundColor))
        .labcordMotion(.state, value: foregroundColor)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(idealWidth: width, maxWidth: width, minHeight: height, alignment: .leading)
        .background {
            Rectangle()
                .fill((fillColor ?? Color("General/Fill/Secondary", bundle: .module)))
                .opacity(fillColor == nil ? 0 : 1)
                .labcordMotion(.state, value: fillColor)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: layout.radiusSm))
        .contentShape(RoundedRectangle(cornerRadius: layout.radiusSm))
    }

    private var resolvedSize: ComponentSize {
        size ?? ComponentSize(controlSize)
    }

    private var effectiveState: DropdownState {
        if !isEnabled || state == .disabled {
            return .disabled
        }
        if state == .error {
            return .error
        }
        if state == .open || isPresented {
            return .open
        }
        return state
    }

    private var width: CGFloat {
        switch resolvedSize {
        case .small:
            return 132
        case .medium:
            return 220
        case .large:
            return 370
        }
    }

    private var height: CGFloat {
        switch resolvedSize {
        case .small:
            return 34
        case .medium:
            return 44
        case .large:
            return 52
        }
    }

    private var horizontalPadding: CGFloat {
        resolvedSize == .small ? layout.spacing12 : layout.spacing16
    }

    private var verticalPadding: CGFloat {
        switch resolvedSize {
        case .small:
            return 7
        case .medium:
            return 11.5
        case .large:
            return 15
        }
    }

    private var textStyle: TypographyStyle {
        switch resolvedSize {
        case .small:
            return Typography.subheadline
        case .medium:
            return Typography.callout
        case .large:
            return Typography.body
        }
    }

    private var fontTextStyle: Font.TextStyle {
        switch resolvedSize {
        case .small:
            return .subheadline
        case .medium:
            return .callout
        case .large:
            return .body
        }
    }

    private var foregroundColor: Color {
        switch effectiveState {
        case .default: return Color("General/Label/Tertiary", bundle: .module)
        case .filled, .open: return Color("General/Label/Primary", bundle: .module)
        case .disabled: return Color("General/Label/Disabled", bundle: .module)
        case .error: return Color("General/Feedback/Error/Foreground", bundle: .module)
        }
    }

    private var fillColor: Color? {
        switch effectiveState {
        case .disabled: return Color("General/Fill/Secondary", bundle: .module)
        case .error: return Color("General/Feedback/Error/Subtle", bundle: .module)
        case .default, .filled, .open:
            return nil
        }
    }

}

public struct DropdownTrigger<MenuContent: View>: View {
    private let value: String
    private let size: ComponentSize?
    private let state: DropdownState
    private let isPresented: Bool
    private let menuContent: () -> MenuContent
    @State private var isPressed = false

    public init(
        value: String,
        size: ComponentSize? = nil,
        state: DropdownState = .default,
        isPresented: Bool = false,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) {
        self.value = value
        self.size = size
        self.state = state
        self.isPresented = isPresented
        self.menuContent = menuContent
    }

    public var body: some View {
#if os(watchOS)
        triggerLabel
#else
        Menu(content: menuContent) {
            triggerLabel.opacity(0)
        }
        .buttonStyle(DropdownMenuPressStyle(isPressed: $isPressed))
        .background {
            triggerLabel
                .labcordPressFeedback(isPressed, isSubtle: true)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityLabel(Text(value))
        .disabled(state == .disabled)
#endif
    }

    private var triggerLabel: some View {
        DropdownTriggerLabel(
            value: value,
            size: size,
            state: state,
            isPresented: isPresented
        )
    }
}

private struct DropdownMenuPressStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
            .onDisappear { isPressed = false }
    }
}

#Preview("드롭다운") {
    _ = FontRegistration.register()
    return DropdownTrigger(value: "옵션 선택") {
        Button("옵션 1") {}
    }
}
