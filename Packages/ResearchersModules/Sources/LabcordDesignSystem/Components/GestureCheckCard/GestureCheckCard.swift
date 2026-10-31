import SwiftUI

public struct GestureCheckCard: View {
    private let title: String
    private let subtitle: String
    private let showsFollowingIcon: Bool

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
        HStack(alignment: .center, spacing: LayoutTokens.spacing4) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing4) {
                Text(title)
                    .typography(Typography.bodySemiBold)
                Text(subtitle)
                    .typography(Typography.subheadline)
            }
            .foregroundStyle(Color(.Experiment.Fill.white))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if showsFollowingIcon {
                LabcordIconArtwork(icon: .checkBold, size: 34)
                    .foregroundStyle(Color(.Experiment.Brand.primary))
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, LayoutTokens.spacing16)
        .padding(.vertical, LayoutTokens.spacing12)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay { Rectangle().fill(Color(.Experiment.Fill.dark)) }
        }
        .clipShape(RoundedRectangle(cornerRadius: LayoutTokens.radiusSm, style: .circular))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: showsFollowingIcon)
        .accessibilityElement(children: .combine)
    }
}

public typealias GestureToast = GestureCheckCard

#Preview("제스처 인식 안내") {
    _ = FontRegistration.register()
    return GestureCheckCard(title: "토스트 문구입니다.", subtitle: "토스트 문구입니다.")
        .frame(maxWidth: 241)
        .padding()
}
