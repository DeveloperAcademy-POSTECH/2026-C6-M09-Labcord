import SwiftUI

public enum ProtocolUploadButtonState: String, CaseIterable, Sendable {
    case selected
    case `default`
    case disabled
}

public struct ProtocolUploadButton: View {
    private let title: String
    private let description: String
    private let showDescription: Bool
    private let state: ProtocolUploadButtonState
    private let action: () -> Void

    public init(
        _ title: String,
        description: String,
        state: ProtocolUploadButtonState,
        showDescription: Bool = true,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title, description: description, state: state,
            showDescription: showDescription, action: action
        )
    }

    public init(
        title: String = "파일",
        description: String = "pdf, xlsx, docx 파일을 업로드해 주세요\n용량 제한: 최대 1GB",
        state: ProtocolUploadButtonState = .default,
        showDescription: Bool = true,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.description = description
        self.showDescription = showDescription
        self.state = state
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing4) {
                Text(title)
                    .typography(Typography.calloutSemiBold)
                    .fixedSize(horizontal: false, vertical: true)

                if showDescription {
                    Text(description)
                        .typography(Typography.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LayoutTokens.spacing16)
        }
        .buttonStyle(ProtocolUploadButtonStyle(state: state, showDescription: showDescription))
        .disabled(state == .disabled)
        .accessibilityHint(Text("프로토콜 파일을 선택합니다"))
    }

}

private struct ProtocolUploadButtonStyle: ButtonStyle {
    let state: ProtocolUploadButtonState
    let showDescription: Bool

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .frame(
                maxWidth: .infinity,
                minHeight: showDescription ? 79 : 55,
                alignment: .topLeading
            )
            .background {
                RoundedRectangle(cornerRadius: LayoutTokens.radiusSm)
                    .fill(backgroundColor)
                    .labcordMotion(.state, value: backgroundColor)
            }
            .clipShape(RoundedRectangle(cornerRadius: LayoutTokens.radiusSm))
            .overlay {
                RoundedRectangle(cornerRadius: LayoutTokens.radiusSm)
                    .strokeBorder(borderColor ?? .clear, lineWidth: 1)
                    .labcordMotion(.state, value: effectiveState.rawValue)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: LayoutTokens.radiusSm))
            .labcordPressFeedback(configuration.isPressed, isSubtle: true)
    }

    private var effectiveState: ProtocolUploadButtonState {
        isEnabled ? state : .disabled
    }

    private var foregroundColor: Color {
        effectiveState == .disabled
            ? Color(.General.Label.disabled)
            : Color(.General.Label.primary)
    }

    private var backgroundColor: Color {
        switch effectiveState {
        case .selected:
            Color(.General.Fill.selected)
        case .default:
            .clear
        case .disabled:
            Color(.General.Fill.disabled)
        }
    }

    private var borderColor: Color? {
        switch effectiveState {
        case .selected:
            Color(.General.Border.focused)
        case .default:
            Color(.General.Border.`default`)
        case .disabled:
            nil
        }
    }
}

#Preview("프로토콜 업로드 · 기본") {
    _ = FontRegistration.register()
    return ProtocolUploadButton()
        .frame(width: 370)
        .padding()
}

#Preview("프로토콜 업로드 · 큰 글자") {
    _ = FontRegistration.register()
    return ProtocolUploadButton(title: "연구 프로토콜", description: "PDF와 XLSX 파일을 선택해 주세요")
        .environment(\.dynamicTypeSize, .accessibility3)
        .frame(width: 370)
        .padding()
}

#Preview("프로토콜 업로드 · 주요 상태") {
    _ = FontRegistration.register()
    return VStack {
        ProtocolUploadButton(state: .selected)
        ProtocolUploadButton(state: .default)
        ProtocolUploadButton(state: .disabled)
        ProtocolUploadButton(showDescription: false)
    }
    .frame(width: 370)
    .padding()
}
