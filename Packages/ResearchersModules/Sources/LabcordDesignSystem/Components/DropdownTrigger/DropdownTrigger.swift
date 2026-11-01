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
        HStack(spacing: LayoutTokens.spacing8) {
            Text(value)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            IconArtwork(
                icon: effectiveState == .open ? .caretUp : .caretDown,
                size: iconSize,
                relativeTo: fontTextStyle
            )
            .foregroundStyle(iconColor)
        }
        .typography(textStyle)
        .foregroundStyle((foregroundColor))
        .labcordMotion(.state, value: foregroundColor)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(idealWidth: width, maxWidth: width, minHeight: height, alignment: .leading)
        .background {
            Rectangle()
                .fill((fillColor ?? Color(.General.Fill.secondary)))
                .opacity(fillColor == nil ? 0 : 1)
                .labcordMotion(.state, value: fillColor)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: LayoutTokens.radiusSm))
        .contentShape(RoundedRectangle(cornerRadius: LayoutTokens.radiusSm))
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
        case .large, .extraLarge:
            return 370
        }
    }

    private var height: CGFloat {
        switch resolvedSize {
        case .small:
            return 34
        case .medium:
            return 44
        case .large, .extraLarge:
            return 52
        }
    }

    private var horizontalPadding: CGFloat {
        resolvedSize == .small ? LayoutTokens.spacing12 : LayoutTokens.spacing16
    }

    private var verticalPadding: CGFloat {
        switch resolvedSize {
        case .small:
            return 7
        case .medium:
            return 11.5
        case .large, .extraLarge:
            return 15
        }
    }

    private var textStyle: TypographyStyle {
        switch resolvedSize {
        case .small:
            return Typography.subheadline
        case .medium:
            return Typography.callout
        case .large, .extraLarge:
            return Typography.body
        }
    }

    private var fontTextStyle: Font.TextStyle {
        switch resolvedSize {
        case .small:
            return .subheadline
        case .medium:
            return .callout
        case .large, .extraLarge:
            return .body
        }
    }

    private var iconSize: CGFloat {
        switch resolvedSize {
        case .small: 16
        case .medium: 20
        case .large, .extraLarge: 24
        }
    }

    private var iconColor: Color {
        effectiveState == .default ? Color(.General.Label.primary) : foregroundColor
    }

    private var foregroundColor: Color {
        switch effectiveState {
        case .default: return Color(.General.Label.tertiary)
        case .filled, .open: return Color(.General.Label.primary)
        case .disabled: return Color(.General.Label.disabled)
        case .error: return Color(.General.Feedback.Error.foreground)
        }
    }

    private var fillColor: Color? {
        switch effectiveState {
        case .disabled: return Color(.General.Fill.disabled)
        case .error: return Color(.General.Feedback.Error.subtle)
        case .default, .filled, .open:
            return nil
        }
    }

}

public struct DropdownOption: Identifiable {
    public let id: UUID
    fileprivate let title: String
    fileprivate let role: ButtonRole?
    fileprivate let isDisabled: Bool
    fileprivate let action: () -> Void

    public init(
        id: UUID = UUID(),
        title: String,
        role: ButtonRole? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.role = role
        self.isDisabled = isDisabled
        self.action = action
    }
}

public struct DropdownTrigger<MenuContent: View>: View {
    private let value: String
    private let size: ComponentSize?
    private let state: DropdownState
    private let displayedAsPresented: Bool
    private let usesNativeMenu: Bool
    private let externalPresentation: Binding<Bool>?
    private let options: [DropdownOption]?
    private let menuContent: (@escaping () -> Void) -> MenuContent
    @Environment(\.isEnabled) private var isEnabled
    @State private var internalPresentation = false
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
        self.displayedAsPresented = isPresented
        self.usesNativeMenu = true
        self.externalPresentation = nil
        self.options = nil
        self.menuContent = { _ in menuContent() }
    }

    public init(
        value: String,
        size: ComponentSize? = nil,
        state: DropdownState = .default,
        isPresented: Binding<Bool>? = nil,
        @ViewBuilder dismissableContent: @escaping (@escaping () -> Void) -> MenuContent
    ) {
        self.value = value
        self.size = size
        self.state = state
        self.displayedAsPresented = false
        self.usesNativeMenu = false
        self.externalPresentation = isPresented
        self.options = nil
        self.menuContent = dismissableContent
    }

    public init(
        value: String,
        size: ComponentSize? = nil,
        state: DropdownState = .default,
        isPresented: Binding<Bool>? = nil,
        options: [DropdownOption]
    ) where MenuContent == EmptyView {
        self.value = value
        self.size = size
        self.state = state
        self.displayedAsPresented = false
        self.usesNativeMenu = false
        self.externalPresentation = isPresented
        self.options = options
        self.menuContent = { _ in EmptyView() }
    }

    public var body: some View {
#if os(watchOS)
        triggerLabel
#else
        if usesNativeMenu {
            Menu {
                menuContent(closeMenu)
            } label: {
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
        } else {
            customTrigger
        }
#endif
    }

#if !os(watchOS)
    private var customTrigger: some View {
        Button {
            presentation.wrappedValue = true
        } label: {
            triggerLabel
        }
        .buttonStyle(DropdownMenuPressStyle(isPressed: $isPressed))
        .labcordPressFeedback(isPressed, isSubtle: true)
        .accessibilityLabel(Text(value))
        .accessibilityValue(Text(presentation.wrappedValue ? "열림" : "닫힘"))
        .disabled(state == .disabled)
        .popover(isPresented: presentation, arrowEdge: .bottom) {
            menu
                .presentationCompactAdaptation(.popover)
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { closeMenu() }
        }
        .onChange(of: state) { _, newState in
            if newState == .disabled { closeMenu() }
        }
        .onChange(of: presentation.wrappedValue) { _, presented in
            if presented && (!isEnabled || state == .disabled) { closeMenu() }
        }
        .onChange(of: externalPresentation?.wrappedValue, initial: true) { _, presented in
            if presented == true && (!isEnabled || state == .disabled) { closeMenu() }
        }
        .onAppear {
            if !isEnabled || state == .disabled { closeMenu() }
        }
    }
#endif

    private var presentation: Binding<Bool> {
        let underlying = externalPresentation ?? $internalPresentation
        return Binding(
            get: { isEnabled && state != .disabled && underlying.wrappedValue },
            set: { underlying.wrappedValue = $0 }
        )
    }

    @ViewBuilder
    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let options {
                ForEach(options) { option in
                    Button(role: option.role) {
                        closeMenu()
                        option.action()
                    } label: {
                        Text(option.title)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .disabled(option.isDisabled)
                }
            } else {
                menuContent(closeMenu)
            }
        }
        .padding(LayoutTokens.spacing8)
        .accessibilityAction(.escape, closeMenu)
    }

    private func closeMenu() {
        presentation.wrappedValue = false
    }

    private var triggerLabel: some View {
        DropdownTriggerLabel(
            value: value,
            size: size,
            state: state,
            isPresented: displayedAsPresented || presentation.wrappedValue
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
    return DropdownTrigger(value: "옵션 선택", options: [
        DropdownOption(title: "옵션 1") {}
    ])
}

#Preview("드롭다운 · 열림") {
    _ = FontRegistration.register()
    return DropdownTriggerLabel(value: "옵션 선택", state: .open)
}

#Preview("드롭다운 · 외부 상태와 사용자 콘텐츠") {
    @Previewable @State var isPresented = false
    DropdownTrigger(value: "옵션 선택", isPresented: $isPresented) { close in
        Button("선택", action: close)
    }
}
