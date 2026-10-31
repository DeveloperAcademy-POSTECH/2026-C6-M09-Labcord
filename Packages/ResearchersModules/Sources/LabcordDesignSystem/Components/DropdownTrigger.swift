import SwiftUI

public enum LabcordDropdownState: String, Sendable {
    case `default`
    case filled
    case open
    case disabled
    case error
}

public struct LabcordDropdownTriggerLabel: View {
    private let value: String
    private let size: LabcordControlSize?
    private let state: LabcordDropdownState
    private let isPresented: Bool

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.labcordTheme) private var theme

    public init(
        value: String,
        size: LabcordControlSize? = nil,
        state: LabcordDropdownState = .default,
        isPresented: Bool = false
    ) {
        self.value = value
        self.size = size
        self.state = state
        self.isPresented = isPresented
    }

    public var body: some View {
        HStack(spacing: theme.layout.spacing8) {
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
        .foregroundStyle(LabcordColor(foregroundToken))
        .labcordMotion(.state, value: foregroundToken)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(idealWidth: width, maxWidth: width, minHeight: height, alignment: .leading)
        .background {
            Rectangle()
                .fill(LabcordColor(fillToken ?? .fillSecondary))
                .opacity(fillToken == nil ? 0 : 1)
                .labcordMotion(.state, value: fillToken)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.layout.radiusSm))
        .contentShape(RoundedRectangle(cornerRadius: theme.layout.radiusSm))
    }

    private var resolvedSize: LabcordControlSize {
        size ?? LabcordControlSize(controlSize)
    }

    private var effectiveState: LabcordDropdownState {
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
        resolvedSize == .small ? theme.layout.spacing12 : theme.layout.spacing16
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

    private var foregroundToken: ColorToken {
        switch effectiveState {
        case .default:
            return .labelTertiary
        case .filled, .open:
            return .labelPrimary
        case .disabled:
            return .labelDisabled
        case .error:
            return .feedbackErrorForeground
        }
    }

    private var fillToken: ColorToken? {
        switch effectiveState {
        case .disabled:
            return .fillSecondary
        case .error:
            return .feedbackErrorSubtle
        case .default, .filled, .open:
            return nil
        }
    }

}

public struct LabcordDropdownTrigger<MenuContent: View>: View {
    private let value: String
    private let size: LabcordControlSize?
    private let state: LabcordDropdownState
    private let isPresented: Bool
    private let menuContent: () -> MenuContent
    @State private var isPressed = false

    public init(
        value: String,
        size: LabcordControlSize? = nil,
        state: LabcordDropdownState = .default,
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
        LabcordDropdownTriggerLabel(
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
