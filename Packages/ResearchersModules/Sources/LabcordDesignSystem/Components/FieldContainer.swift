import SwiftUI

public struct FieldContainer<Content: View>: View {
    private let label: String?
    private let required: Bool
    private let feedback: String?
    private let showTitle: Bool
    private let showFeedback: Bool
    private let isError: Bool
    private let isDisabled: Bool
    private let content: () -> Content

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.labcordTheme) private var theme

    public init(
        label: String? = "타이틀",
        required: Bool = true,
        feedback: String? = "피드백 텍스트가 보입니다.",
        showTitle: Bool = true,
        showFeedback: Bool = true,
        isError: Bool = false,
        isDisabled: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.required = required
        self.feedback = feedback
        self.showTitle = showTitle
        self.showFeedback = showFeedback
        self.isError = isError
        self.isDisabled = isDisabled
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.layout.spacing8) {
            if showTitle {
                HStack(alignment: .firstTextBaseline, spacing: theme.layout.spacing4) {
                    if let label {
                        Text(label)
                            .typography(Typography.calloutEmphasized)
                            .foregroundStyle(LabcordColor(labelToken))
                            .labcordMotion(.state, value: labelToken)
                    }

                    if required {
                        Text("*")
                            .typography(Typography.calloutEmphasized)
                            .foregroundStyle(LabcordColor(requiredToken))
                            .labcordMotion(.state, value: requiredToken)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            content()
                .disabled(resolvedIsDisabled)

            Group {
                if showFeedback, let feedback {
                    Text(feedback)
                        .typography(Typography.subheadline)
                        .foregroundStyle(LabcordColor(feedbackToken))
                        .labcordMotion(.state, value: feedbackToken)
                        .contentTransition(.opacity)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
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

    private var labelToken: ColorToken {
        resolvedIsDisabled ? .labelDisabled : .labelSecondary
    }

    private var requiredToken: ColorToken {
        resolvedIsDisabled ? .labelDisabled : .feedbackErrorForeground
    }

    private var feedbackToken: ColorToken {
        if resolvedIsDisabled {
            return .labelDisabled
        }
        return isError ? .feedbackErrorForeground : .labelSecondary
    }
}

public typealias LabcordFieldContainer<Content: View> = FieldContainer<Content>
