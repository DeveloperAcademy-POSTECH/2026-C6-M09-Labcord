import SwiftUI

#if os(watchOS)
public struct LabcordTextEditorStyle: ViewModifier {
    public init(
        placeholder: Text? = nil,
        isEmpty: Bool = true,
        isFocused: Bool = false,
        isFilled: Bool = false,
        isError: Bool = false,
        isDisabled: Bool = false
    ) {}

    public init(
        placeholder: LocalizedStringKey,
        isEmpty: Bool = true,
        isFocused: Bool = false,
        isFilled: Bool = false,
        isError: Bool = false,
        isDisabled: Bool = false
    ) {}

    public init(
        placeholder: String,
        isEmpty: Bool = true,
        isFocused: Bool = false,
        isFilled: Bool = false,
        isError: Bool = false,
        isDisabled: Bool = false
    ) {}

    public func body(content: Content) -> some View {
        content
    }
}
#else
public struct LabcordTextEditorStyle: ViewModifier {
    private let placeholder: Text?
    private let isEmpty: Bool
    private let isFocused: Bool
    private let isFilled: Bool
    private let isError: Bool
    private let isDisabled: Bool

    @State private var inputID = UUID()

    @Environment(\.isEnabled) private var isEnabled
    private let layout = LayoutTokens()
    @ScaledMetric(relativeTo: .subheadline) private var editorHeight: CGFloat = 120

    public init(
        placeholder: Text? = nil,
        isEmpty: Bool = true,
        isFocused: Bool = false,
        isFilled: Bool = false,
        isError: Bool = false,
        isDisabled: Bool = false
    ) {
        self.placeholder = placeholder
        self.isEmpty = isEmpty
        self.isFocused = isFocused
        self.isFilled = isFilled
        self.isError = isError
        self.isDisabled = isDisabled
    }

    public init(
        placeholder: LocalizedStringKey,
        isEmpty: Bool = true,
        isFocused: Bool = false,
        isFilled: Bool = false,
        isError: Bool = false,
        isDisabled: Bool = false
    ) {
        self.init(
            placeholder: Text(placeholder),
            isEmpty: isEmpty,
            isFocused: isFocused,
            isFilled: isFilled,
            isError: isError,
            isDisabled: isDisabled
        )
    }

    public init(
        placeholder: String,
        isEmpty: Bool = true,
        isFocused: Bool = false,
        isFilled: Bool = false,
        isError: Bool = false,
        isDisabled: Bool = false
    ) {
        self.init(
            placeholder: Text(verbatim: placeholder),
            isEmpty: isEmpty,
            isFocused: isFocused,
            isFilled: isFilled,
            isError: isError,
            isDisabled: isDisabled
        )
    }

    public func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            content
                .typography(Typography.subheadline)
                .foregroundStyle((state.foregroundColor))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, layout.spacing12 - 5)
                .padding(.vertical, layout.spacing12 - 8)
                .frame(
                    maxWidth: .infinity,
                    minHeight: editorHeight,
                    maxHeight: editorHeight,
                    alignment: .topLeading
                )

            if isEmpty, let placeholder {
                placeholder
                    .typography(Typography.subheadline)
                    .foregroundStyle((placeholderColor))
                    .padding(.horizontal, layout.spacing12)
                    .padding(.vertical, layout.spacing12)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
            .frame(
                maxWidth: .infinity,
                minHeight: editorHeight,
                maxHeight: editorHeight,
                alignment: .topLeading
            )
            .background((state.backgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: layout.radiusSm, style: .circular))
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: layout.radiusSm, style: .circular)
                    .strokeBorder((state.borderColor), lineWidth: 1)
                    .labcordMotion(.state, value: state.borderColor)
                    .allowsHitTesting(false)
            }
            .id(inputID)
            .background {
                GeometryReader { geometry in
                    let frame = geometry.frame(in: .global)
                    let input = LabcordFocusedInput(id: inputID, frame: frame)
                    Color.clear.preference(
                        key: LabcordFocusedInputPreferenceKey.self,
                        value: isFocused && isEnabled && !isDisabled ? [input] : []
                    )
                }
                .allowsHitTesting(false)
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

    private var placeholderColor: Color {
        switch state {
        case .disabled:
            return Color("General/Label/Disabled", bundle: .module)
        default:
            return Color("General/Label/Tertiary", bundle: .module)
        }
    }

}
#endif

public extension View {
    func labcordTextEditorStyle(_ style: LabcordTextEditorStyle = .init()) -> some View {
        modifier(style)
    }

    func labcordTextEditorStyle(
        text: String,
        focus: FocusState<Bool>.Binding,
        placeholder: Text? = nil,
        isError: Bool = false
    ) -> some View {
        labcordTextEditorStyle(
            LabcordTextEditorStyle(
                placeholder: placeholder,
                isEmpty: text.isEmpty,
                isFocused: focus.wrappedValue,
                isFilled: !text.isEmpty,
                isError: isError
            )
        )
        .labcordInputFocus(focus)
    }

    func labcordTextEditorStyle<Value: Hashable>(
        text: String,
        focus: FocusState<Value?>.Binding,
        equals value: Value,
        placeholder: Text? = nil,
        isError: Bool = false
    ) -> some View {
        labcordTextEditorStyle(
            LabcordTextEditorStyle(
                placeholder: placeholder,
                isEmpty: text.isEmpty,
                isFocused: focus.wrappedValue == value,
                isFilled: !text.isEmpty,
                isError: isError
            )
        )
        .labcordInputFocus(focus, equals: value)
    }
}

#if !os(watchOS)
#Preview("텍스트 에디터") {
    @Previewable @State var text = "실험 기록을 입력해 주세요."
    _ = FontRegistration.register()
    return TextEditor(text: $text)
        .labcordTextEditorStyle(.init(isEmpty: false, isFilled: true))
}
#endif
