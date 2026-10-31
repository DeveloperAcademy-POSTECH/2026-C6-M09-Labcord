import SwiftUI

public enum LabcordInputState: Sendable {
    case empty
    case focused
    case filled
    case error
    case disabled
}

extension LabcordInputState {
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

    var foregroundToken: ColorToken {
        switch self {
        case .empty:
            return .labelTertiary
        case .focused, .filled:
            return .labelPrimary
        case .error:
            return .feedbackErrorForeground
        case .disabled:
            return .labelDisabled
        }
    }

    var backgroundToken: ColorToken {
        switch self {
        case .error:
            return .feedbackErrorSubtle
        case .disabled:
            return .fillDisabled
        case .empty, .focused, .filled:
            return .backgroundGroupedSecondary
        }
    }

    var borderToken: ColorToken {
        switch self {
        case .focused:
            return .borderFocused
        case .error:
            return .feedbackErrorForeground
        case .empty, .filled, .disabled:
            return .borderDefault
        }
    }
}

public struct LabcordTextFieldStyle: TextFieldStyle {
    private let size: LabcordControlSize?
    private let isFocused: Bool
    private let isFilled: Bool
    private let isError: Bool
    private let isDisabled: Bool

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    public init(
        size: LabcordControlSize? = nil,
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
            foregroundToken: state.foregroundToken,
            borderToken: state.borderToken,
            backgroundToken: state.backgroundToken,
            height: height
        )
    }

    private var resolvedSize: LabcordControlSize {
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

    private var state: LabcordInputState {
        LabcordInputState(
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
    let size: LabcordControlSize
    let foregroundToken: ColorToken
    let borderToken: ColorToken
    let backgroundToken: ColorToken
    let height: CGFloat

    @Environment(\.labcordTheme) private var theme

    nonisolated init(
        configuration: TextField<Label>,
        size: LabcordControlSize,
        foregroundToken: ColorToken,
        borderToken: ColorToken,
        backgroundToken: ColorToken,
        height: CGFloat
    ) {
        self.configuration = configuration
        self.size = size
        self.foregroundToken = foregroundToken
        self.borderToken = borderToken
        self.backgroundToken = backgroundToken
        self.height = height
    }

    var body: some View {
        configuration
            .typography(inputTypography)
            .foregroundStyle(LabcordColor(foregroundToken))
            .tint(LabcordColor(.brandPrimary))
            .padding(.horizontal, theme.layout.spacing8)
            .frame(
                maxWidth: .infinity,
                minHeight: height,
                alignment: .leading
            )
            .background(LabcordColor(backgroundToken))
            .clipShape(RoundedRectangle(cornerRadius: theme.layout.radiusSm, style: .circular))
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: theme.layout.radiusSm, style: .circular)
                    .strokeBorder(LabcordColor(borderToken), lineWidth: 1)
                    .labcordMotion(.state, value: borderToken)
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

public extension TextFieldStyle where Self == LabcordTextFieldStyle {
    static func labcord(
        size: LabcordControlSize? = nil,
        isFocused: Bool = false,
        isFilled: Bool = false,
        isError: Bool = false,
        isDisabled: Bool = false
    ) -> LabcordTextFieldStyle {
        LabcordTextFieldStyle(
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
        size: LabcordControlSize? = nil,
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
        size: LabcordControlSize? = nil,
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
