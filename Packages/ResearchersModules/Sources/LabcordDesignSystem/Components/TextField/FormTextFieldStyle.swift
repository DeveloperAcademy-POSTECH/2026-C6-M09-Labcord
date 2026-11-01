import SwiftUI

public enum InputState: Sendable {
    case empty
    case focused
    case filled
    case error
    case disabled
}

extension InputState {
    init(
        isEnabled: Bool,
        isDisabled: Bool,
        isError: Bool,
        isFocused: Bool,
        isFilled: Bool
    ) {
        if isDisabled || !isEnabled {
            self = .disabled
        } else if isError {
            self = .error
        } else if isFocused {
            self = .focused
        } else if isFilled {
            self = .filled
        } else {
            self = .empty
        }
    }

    var foregroundColor: Color {
        switch self {
        case .empty: return Color(.General.Label.tertiary)
        case .focused, .filled: return Color(.General.Label.primary)
        case .error: return Color(.General.Feedback.Error.foreground)
        case .disabled: return Color(.General.Label.disabled)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .error: return Color(.General.Feedback.Error.subtle)
        case .disabled: return Color(.General.Fill.disabled)
        case .empty, .focused, .filled:
            return Color(.General.Background.Grouped.secondary)
        }
    }

    var borderColor: Color {
        switch self {
        case .focused: return Color(.General.Border.focused)
        case .error: return Color(.General.Feedback.Error.foreground)
        case .empty, .filled, .disabled: return Color(.General.Border.`default`)
        }
    }
}

public struct FormTextFieldStyle: TextFieldStyle {
    private let size: ComponentSize?
    private let isFocused: Bool
    private let isFilled: Bool
    private let isError: Bool
    private let isDisabled: Bool

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    public init(
        size: ComponentSize? = nil,
        isFocused: Bool = false,
        isFilled: Bool = false,
        isError: Bool = false,
        isDisabled: Bool = false
    ) {
        self.size = size
        self.isFocused = isFocused
        self.isFilled = isFilled
        self.isError = isError
        self.isDisabled = isDisabled
    }

    // swiftlint:disable:next identifier_name
    public func _body(configuration: TextField<Self._Label>) -> some View {
        LabcordTextFieldBody(
            configuration: configuration,
            size: resolvedSize,
            foregroundColor: state.foregroundColor,
            borderColor: state.borderColor,
            backgroundColor: state.backgroundColor,
            height: height
        )
    }

    private var resolvedSize: ComponentSize {
        if let size { return size }
        switch controlSize {
        case .mini, .small:
            return .small
        case .regular, .large, .extraLarge:
            return .large
        @unknown default:
            return .large
        }
    }

    private var state: InputState {
        InputState(
            isEnabled: isEnabled,
            isDisabled: isDisabled,
            isError: isError,
            isFocused: isFocused,
            isFilled: isFilled
        )
    }

    private var height: CGFloat {
        switch resolvedSize {
        case .small, .medium:
            return 44
        case .large:
            return 52
        }
    }
}

private struct LabcordTextFieldBody<Label: View>: View {
    nonisolated(unsafe) let configuration: TextField<Label>
    let size: ComponentSize
    let foregroundColor: Color
    let borderColor: Color
    let backgroundColor: Color
    let height: CGFloat

    nonisolated init(
        configuration: TextField<Label>,
        size: ComponentSize,
        foregroundColor: Color,
        borderColor: Color,
        backgroundColor: Color,
        height: CGFloat
    ) {
        self.configuration = configuration
        self.size = size
        self.foregroundColor = foregroundColor
        self.borderColor = borderColor
        self.backgroundColor = backgroundColor
        self.height = height
    }

    var body: some View {
        configuration
            .typography(inputTypography)
            .foregroundStyle((foregroundColor))
            .tint((Color(.General.Brand.primary)))
            .padding(.horizontal, LayoutTokens.spacing8)
            .frame(
                maxWidth: .infinity,
                minHeight: height,
                alignment: .leading
            )
            .background((backgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: LayoutTokens.radiusSm, style: .circular))
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: LayoutTokens.radiusSm, style: .circular)
                    .strokeBorder((borderColor), lineWidth: 1)
                    .labcordMotion(.state, value: borderColor)
                    .allowsHitTesting(false)
            }
    }

    private var inputTypography: TypographyStyle {
        switch size {
        case .small, .medium:
            return Typography.subheadline
        case .large:
            return Typography.body
        }
    }
}

public extension TextFieldStyle where Self == FormTextFieldStyle {
    static func labcord(
        size: ComponentSize? = nil,
        isFocused: Bool = false,
        isFilled: Bool = false,
        isError: Bool = false,
        isDisabled: Bool = false
    ) -> FormTextFieldStyle {
        FormTextFieldStyle(
            size: size,
            isFocused: isFocused,
            isFilled: isFilled,
            isError: isError,
            isDisabled: isDisabled
        )
    }
}

public extension View {
    func labcordTextFieldStyle(
        text: String,
        focus: FocusState<Bool>.Binding,
        size: ComponentSize? = nil,
        isError: Bool = false
    ) -> some View {
        textFieldStyle(
            .labcord(
                size: size,
                isFocused: focus.wrappedValue,
                isFilled: !text.isEmpty,
                isError: isError
            )
        )
        .labcordInputFocus(focus)
    }

    func labcordTextFieldStyle<Value: Hashable>(
        text: String,
        focus: FocusState<Value?>.Binding,
        equals value: Value,
        size: ComponentSize? = nil,
        isError: Bool = false
    ) -> some View {
        textFieldStyle(
            .labcord(
                size: size,
                isFocused: focus.wrappedValue == value,
                isFilled: !text.isEmpty,
                isError: isError
            )
        )
        .labcordInputFocus(focus, equals: value)
    }
}

#Preview("텍스트 필드") {
    @Previewable @State var text = "실험 이름"
    _ = FontRegistration.register()
    return TextField("실험 이름", text: $text)
        .textFieldStyle(.labcord(isFilled: true))
}
