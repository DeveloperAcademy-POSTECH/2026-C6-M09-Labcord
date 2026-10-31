import SwiftUI

public struct GestureToast: View {
    private let title: String
    private let subtitle: String
    private let showsFollowingIcon: Bool
    private let layout = LayoutTokens()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        title: String,
        subtitle: String,
        showsFollowingIcon: Bool = true
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsFollowingIcon = showsFollowingIcon
    }

    public var body: some View {
        HStack(alignment: .center, spacing: layout.spacing4) {
            VStack(alignment: .leading, spacing: layout.spacing4) {
                Text(title)
                    .typography(Typography.bodyEmphasized)
                Text(subtitle)
                    .typography(Typography.subheadline)
            }
            .foregroundStyle(.labcord(.fillWhite))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if showsFollowingIcon {
                LabcordIconArtwork(icon: .checkCircleFill, size: 34)
                    .foregroundStyle(.labcord(.brandPrimary))
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, layout.spacing16)
        .padding(.vertical, layout.spacing12)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay { Rectangle().fill(.labcord(.fillDark)) }
        }
        .clipShape(RoundedRectangle(cornerRadius: layout.radiusSm, style: .circular))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: showsFollowingIcon)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("제스처 인식 안내") {
    _ = FontRegistration.register()
    return GestureToast(title: "토스트 문구입니다.", subtitle: "토스트 문구입니다.")
        .frame(maxWidth: 241)
        .padding()
        .labcordTheme(LabcordTheme(context: .experiment))
}
#endif
