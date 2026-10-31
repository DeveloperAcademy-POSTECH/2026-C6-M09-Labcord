import SwiftUI

public struct GestureGuideItem<Media: View>: View {
    public enum Layout: String, CaseIterable, Sendable {
        case portrait
        case landscape
    }

    private let title: String
    private let description: String
    private let layout: Layout
    private let media: Media

    @Environment(\.labcordTheme) private var theme

    public init(
        title: String = "음성 녹음",
        description: String = "손바닥을 활짝 펼쳤다가 주먹 쥐기",
        layout: Layout = .landscape,
        @ViewBuilder media: () -> Media
    ) {
        self.title = title
        self.description = description
        self.layout = layout
        self.media = media()
    }

    public var body: some View {
        arrangedContent
            .padding(theme.layout.spacing12)
            .frame(idealWidth: width, maxWidth: width)
            .background(
                .labcord(.fillInverse),
                in: RoundedRectangle(cornerRadius: theme.layout.radiusMd)
            )
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var arrangedContent: some View {
        switch layout {
        case .portrait:
            VStack(spacing: theme.layout.spacing10) {
                gestureMedia
                textContent
            }
        case .landscape:
            HStack(spacing: theme.layout.spacing8) {
                gestureMedia
                textContent
            }
        }
    }

    private var gestureMedia: some View {
        media
            .frame(width: 90, height: 100)
            .clipped()
    }

    private var textContent: some View {
        VStack(
            alignment: layout == .portrait ? .center : .leading,
            spacing: theme.layout.spacing4
        ) {
            Text(title)
                .typography(Typography.headline)
                .frame(maxWidth: .infinity, alignment: textAlignment)

            Text(description)
                .typography(Typography.subheadline)
                .frame(maxWidth: .infinity, alignment: textAlignment)
        }
        .foregroundStyle(.labcord(.labelInverse))
        .multilineTextAlignment(layout == .portrait ? .center : .leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: textAlignment)
    }

    private var width: CGFloat {
        layout == .portrait ? 380 / 3 : 321
    }

    private var textAlignment: Alignment {
        layout == .portrait ? .center : .leading
    }
}
