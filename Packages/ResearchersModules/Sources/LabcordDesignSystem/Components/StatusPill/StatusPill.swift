import SwiftUI

public struct StatusPill: View {
    public enum Appearance: Sendable {
        case general, experiment
    }

    private let message: String
    private let appearance: Appearance
    private let showIcon: Bool

    public init(
        _ message: String,
        appearance: Appearance = .experiment,
        showIcon: Bool = true
    ) {
        self.message = message
        self.appearance = appearance
        self.showIcon = showIcon
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            messageContent.frame(minWidth: 169)
            messageContent
        }
            .frame(minHeight: 45)
            .background {
                pillShape
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, appearance == .general ? .light : .dark)
            }
            .background(
                appearance == .general
                    ? Color(.General.Fill.primary) : Color(.Experiment.Fill.primary),
                in: pillShape
            )
            .clipShape(pillShape)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(message))
    }

    private var messageContent: some View {
        HStack(spacing: LayoutTokens.spacing12) {
            Text(message)
                .typography(Typography.calloutSemiBold)
                .foregroundStyle(labelColor)
                .contentTransition(.opacity)
                .labcordMotion(.state, value: message)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if showIcon {
                IconArtwork(icon: .checkBold, size: 20)
                    .foregroundStyle(
                        appearance == .general
                            ? Color(.General.Brand.primary) : Color(.Experiment.Brand.primary)
                    )
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, LayoutTokens.spacing20)
        .padding(.vertical, LayoutTokens.spacing12)
    }

    private var labelColor: Color {
        appearance == .general ? Color(.General.Label.primary) : Color(.Experiment.Label.primary)
    }

    private var pillShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 60, style: .continuous)
    }

}

#Preview("상태 안내 · 기본") {
    _ = FontRegistration.register()
    return StatusPill("3초 후 자동 저장됩니다.")
        .padding()
        .background(Color(.Experiment.Background.primary))
}

#Preview("상태 안내 · 큰 글자") {
    _ = FontRegistration.register()
    return StatusPill("변경한 실험 기록은 3초 후 자동 저장됩니다.")
        .frame(width: 320)
        .environment(\.dynamicTypeSize, .accessibility3)
        .padding()
        .background(Color(.Experiment.Background.primary))
}
