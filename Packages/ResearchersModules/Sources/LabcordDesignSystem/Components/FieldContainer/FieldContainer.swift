import SwiftUI

public struct FieldContainer<Content: View>: View {
    private let label: String?
    private let required: Bool
    private let feedback: String?
    private let showTitle: Bool
    private let showFeedback: Bool
    private let textCount: Int?
    private let textLimit: Int?
    private let showTextCount: Bool
    private let isError: Bool
    private let isDisabled: Bool
    private let content: () -> Content

    @Environment(\.isEnabled) private var isEnabled

    public init(
        label: String? = "타이틀",
        required: Bool = true,
        feedback: String? = "피드백 텍스트가 보입니다.",
        showTitle: Bool = true,
        showFeedback: Bool = true,
        textCount: Int? = nil,
        textLimit: Int? = nil,
        showTextCount: Bool = true,
        isError: Bool = false,
        isDisabled: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.required = required
        self.feedback = feedback
        self.showTitle = showTitle
        self.showFeedback = showFeedback
        self.textCount = textCount
        self.textLimit = textLimit
        self.showTextCount = showTextCount
        self.isError = isError
        self.isDisabled = isDisabled
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing8) {
            if showTitle {
                HStack(alignment: .firstTextBaseline, spacing: LayoutTokens.spacing4) {
                    if let label {
                        Text(label)
                            .typography(Typography.calloutSemiBold)
                            .foregroundStyle((labelColor))
                            .labcordMotion(.state, value: labelColor)
                    }

                    if required {
                        Text("*")
                            .typography(Typography.calloutSemiBold)
                            .foregroundStyle((requiredColor))
                            .labcordMotion(.state, value: requiredColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            content()
                .disabled(resolvedIsDisabled)

            Group {
                if (showFeedback && feedback != nil) || hasTextCount {
                    HStack(alignment: .firstTextBaseline, spacing: LayoutTokens.spacing8) {
                        if showFeedback, let feedback {
                            Text(feedback)
                                .typography(Typography.subheadline)
                                .foregroundStyle(feedbackColor)
                                .labcordMotion(.state, value: feedbackColor)
                                .contentTransition(.opacity)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        } else {
                            Spacer(minLength: 0)
                        }

                        if hasTextCount, let textCount, let textLimit {
                            Text("\(textCount)/\(textLimit)")
                                .typography(Typography.subheadline)
                                .foregroundStyle(textCountColor)
                                .fixedSize(horizontal: true, vertical: false)
                                .accessibilityLabel(Text("글자 수 \(textCount) / \(textLimit)"))
                        }
                    }
                }
            }
            .labcordMotion(.state, value: feedback)
            .labcordMotion(.state, value: showFeedback)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resolvedIsDisabled: Bool {
        isDisabled || !isEnabled
    }

    private var hasTextCount: Bool {
        showTextCount && textCount != nil && textLimit != nil
    }

    private var textCountColor: Color {
        isError && !resolvedIsDisabled
            ? Color(.General.Feedback.Error.foreground)
            : Color(.General.Label.tertiary)
    }

    private var labelColor: Color {
        resolvedIsDisabled
            ? Color(.General.Label.disabled)
            : Color(.General.Label.secondary)
    }

    private var requiredColor: Color {
        resolvedIsDisabled
            ? Color(.General.Label.disabled)
            : Color(.General.Feedback.Error.foreground)
    }

    private var feedbackColor: Color {
        if resolvedIsDisabled {
            return Color(.General.Label.disabled)
        }
        return isError
            ? Color(.General.Feedback.Error.foreground)
            : Color(.General.Label.secondary)
    }
}

#Preview("입력 필드 · 피드백") {
    _ = FontRegistration.register()
    return FieldContainer(label: "실험 이름", feedback: "실험 이름을 입력해 주세요.") {
        TextField("실험 이름", text: .constant(""))
            .textFieldStyle(.labcord())
    }
}

#Preview("입력 필드 · 글자 수") {
    _ = FontRegistration.register()
    return FieldContainer(
        label: "실험 이름", feedback: "실험 이름을 입력해 주세요.",
        textCount: 12, textLimit: 60
    ) {
        TextField("실험 이름", text: .constant(""))
            .textFieldStyle(.labcord())
    }
}
