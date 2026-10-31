import SwiftUI

public struct StatusPill: View {
    private let message: String
    private let layout = LayoutTokens()

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            messageContent.frame(minWidth: 195)
            messageContent
        }
            .frame(minHeight: 46)
            .background {
                pillShape
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
            .background(Color("Experiment/Fill/Primary", bundle: .module), in: pillShape)
            .clipShape(pillShape)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(message))
    }

    private var messageContent: some View {
        Text(message)
            .typography(Typography.bodySemiBold)
            .foregroundStyle(Color("Experiment/Label/Primary", bundle: .module))
            .contentTransition(.opacity)
            .labcordMotion(.state, value: message)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, layout.spacing20)
            .padding(.vertical, layout.spacing12)
    }

    private var pillShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 60, style: .continuous)
    }

}

#Preview("상태 안내 · 기본") {
    _ = FontRegistration.register()
    return StatusPill("3초 후 자동 저장됩니다.")
        .padding()
        .background(Color("Experiment/Background/Primary", bundle: .module))
}

#Preview("상태 안내 · 큰 글자") {
    _ = FontRegistration.register()
    return StatusPill("변경한 실험 기록은 3초 후 자동 저장됩니다.")
        .frame(width: 320)
        .environment(\.dynamicTypeSize, .accessibility3)
        .padding()
        .background(Color("Experiment/Background/Primary", bundle: .module))
}
