import LabcordDesignSystem
import SwiftUI

struct CatalogControlInputScenario: View {
    let isMultiline: Bool

    @State private var value = ""
    @State private var label: String
    @State private var placeholder = "내용을 입력해 주세요"
    @State private var feedback: String
    @State private var required: Bool
    @State private var showsTitle = true
    @State private var showsFeedback = true
    @State private var forcedState: CatalogControlInputState?
    @FocusState private var isFocused: Bool

    init(isMultiline: Bool) {
        self.isMultiline = isMultiline
        _label = State(initialValue: isMultiline ? "메모" : "프로토콜 이름")
        _feedback = State(initialValue: isMultiline
            ? "필요한 관찰 내용을 기록해 주세요." : "입력한 이름을 확인해 주세요.")
        _required = State(initialValue: !isMultiline)
    }

    private var identifier: String { "catalog.scenario.\(isMultiline ? "textArea" : "textField")" }
    private var isError: Bool { forcedState == .error }
    private var isDisabled: Bool { forcedState == .disabled }

    private var state: Binding<CatalogControlInputState> {
        Binding(
            get: {
                if let forcedState { return forcedState }
                if isFocused { return .focused }
                return value.isEmpty ? .empty : .filled
            },
            set: { next in
                forcedState = [.error, .disabled].contains(next) ? next : nil
                if next == .empty { value = "" }
                if next == .filled, value.isEmpty { value = "샘플 입력 내용" }
                isFocused = next == .focused
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldContainer(
                label: label, required: required, feedback: feedback,
                showTitle: showsTitle, showFeedback: showsFeedback,
                isError: isError, isDisabled: isDisabled
            ) {
                nativeInput
            }
            Picker("상태", selection: state) {
                catalogPickerOptions(CatalogControlInputState.allCases, capitalized: false)
            }
            .labcordKeyboardDismissalDisabled()
            .accessibilityIdentifier(identifier + ".state")
            CatalogDisclosureGroup("콘텐츠 옵션", identifier: identifier + ".contentOptions") {
                Toggle("제목 표시", isOn: $showsTitle)
                    .accessibilityIdentifier(identifier + ".showTitle")
                Toggle("안내 문구 표시", isOn: $showsFeedback)
                    .accessibilityIdentifier(identifier + ".showFeedback")
                Toggle("필수 표시", isOn: $required)
                    .accessibilityIdentifier(identifier + ".required")
                CatalogControlTextProperty(title: "표시 제목", value: $label)
                CatalogControlTextProperty(title: "입력 값", value: $value)
                CatalogControlTextProperty(title: "플레이스홀더", value: $placeholder)
                CatalogControlTextProperty(title: "안내 문구", value: $feedback)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused { forcedState = nil }
        }
    }

    @ViewBuilder
    private var nativeInput: some View {
        if isMultiline {
            #if os(watchOS)
            Text(value.isEmpty ? placeholder : value)
                .typography(Typography.subheadline)
                .foregroundStyle(.labcord(value.isEmpty ? .labelTertiary : .labelPrimary))
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .padding(12)
                .background(.labcord(.backgroundGroupedSecondary))
            #else
            TextEditor(text: $value)
                .labcordTextEditorStyle(
                    LabcordTextEditorStyle(
                        placeholder: placeholder, isEmpty: value.isEmpty,
                        isFocused: isFocused, isFilled: !value.isEmpty,
                        isError: isError, isDisabled: isDisabled
                    )
                )
                .labcordInputFocus($isFocused)
                .accessibilityLabel(Text(label))
                .accessibilityIdentifier(identifier + ".preview")
            #endif
        } else {
            TextField(
                placeholder, text: $value,
                prompt: Text(placeholder)
                    .foregroundStyle(.labcord(isDisabled ? .labelDisabled : .labelTertiary))
            )
                .textFieldStyle(
                    LabcordTextFieldStyle(
                        isFocused: isFocused, isFilled: !value.isEmpty,
                        isError: isError, isDisabled: isDisabled
                    )
                )
                .labcordInputFocus($isFocused)
                .accessibilityLabel(Text(label))
                .accessibilityIdentifier(identifier + ".preview")
        }
    }
}

private enum CatalogControlInputState: String, CaseIterable {
    case empty = "Empty"
    case focused = "Focused"
    case filled = "Filled"
    case error = "Error"
    case disabled = "Disabled"
}

struct CatalogControlTextProperty: View {
    let title: String
    @Binding var value: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .typography(Typography.caption1)
                .foregroundStyle(.labcord(.labelSecondary))
            TextField(title, text: $value)
                .labcordTextFieldStyle(text: value, focus: $isFocused, size: .medium)
                .accessibilityLabel(Text(title))
        }
    }
}

struct CatalogDisclosureGroup<Content: View>: View {
    private let title: LocalizedStringKey
    private let identifier: String?
    private let content: () -> Content

    init(
        _ title: LocalizedStringKey, identifier: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.identifier = identifier
        self.content = content
    }

    var body: some View {
        #if os(watchOS)
        VStack(alignment: .leading, spacing: 12) {
            titleLabel
                .typography(Typography.calloutEmphasized)
            content()
        }
        #else
        DisclosureGroup(content: content) { titleLabel }
        #endif
    }

    @ViewBuilder
    private var titleLabel: some View {
        if let identifier {
            Text(title).accessibilityIdentifier(identifier)
        } else {
            Text(title)
        }
    }
}
