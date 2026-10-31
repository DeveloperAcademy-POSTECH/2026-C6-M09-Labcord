import SwiftUI

public enum ProtocolUploadButtonState: String, CaseIterable, Sendable {
    case selected
    case `default`
    case disabled
}

public struct ProtocolUploadButton: View {
    private let title: String
    private let description: String
    private let state: ProtocolUploadButtonState
    private let action: () -> Void

    public init(
        _ title: String,
        description: String,
        state: ProtocolUploadButtonState,
        action: @escaping () -> Void
    ) {
        self.init(title: title, description: description, state: state, action: action)
    }

    public init(
        title: String = "파일",
        description: String = "pdf, xlsx, docx 파일을 업로드해 주세요\n용량 제한: 최대 1GB",
        state: ProtocolUploadButtonState = .selected,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.description = description
        self.state = state
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing4) {
                Text(title)
                    .typography(Typography.bodySemiBold)
                    .fixedSize(horizontal: false, vertical: true)

                Text(description.isEmpty ? Self.defaultDescription : description)
                    .typography(Typography.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LayoutTokens.spacing16)
        }
        .buttonStyle(ProtocolUploadButtonStyle(state: state))
        .disabled(state == .disabled)
        .accessibilityHint(Text("프로토콜 파일을 선택합니다"))
    }

    private static let defaultDescription = "pdf, xlsx, docx 파일을 업로드해 주세요\n용량 제한: 최대 1GB"
}

private struct ProtocolUploadButtonStyle: ButtonStyle {
    let state: ProtocolUploadButtonState

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .frame(
                maxWidth: .infinity,
                minHeight: 100,
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
                    .strokeBorder(Color("General/Border/Focused", bundle: .module), lineWidth: 1)
                    .opacity(state == .selected && isEnabled ? 1 : 0)
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
            ? Color("General/Label/Disabled", bundle: .module)
            : Color("General/Label/Primary", bundle: .module)
    }

    private var backgroundColor: Color {
        switch effectiveState {
        case .selected:
            Color("General/Fill/Selected", bundle: .module)
        case .default:
            Color("General/Fill/Secondary", bundle: .module)
        case .disabled:
            Color("General/Fill/Disabled", bundle: .module)
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
    }
    .frame(width: 370)
    .padding()
}
