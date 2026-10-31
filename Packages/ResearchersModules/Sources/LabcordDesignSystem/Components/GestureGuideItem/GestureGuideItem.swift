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
            .padding(LayoutTokens.spacing12)
            .frame(idealWidth: width, maxWidth: width)
            .background(
                Color("Experiment/Fill/Inverse", bundle: .module),
                in: RoundedRectangle(cornerRadius: LayoutTokens.radiusMd)
            )
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var arrangedContent: some View {
        switch layout {
        case .portrait:
            VStack(spacing: LayoutTokens.spacing10) {
                gestureMedia
                textContent
            }
        case .landscape:
            HStack(spacing: LayoutTokens.spacing8) {
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
            spacing: LayoutTokens.spacing4
        ) {
            Text(title)
                .typography(Typography.headline)
                .frame(maxWidth: .infinity, alignment: textAlignment)

            Text(description)
                .typography(Typography.subheadline)
                .frame(maxWidth: .infinity, alignment: textAlignment)
        }
        .foregroundStyle(Color("Experiment/Label/Inverse", bundle: .module))
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

#Preview("제스처 안내 · 가로와 세로") {
    _ = FontRegistration.register()
    return VStack(spacing: 16) {
        GestureGuideItem(layout: .landscape) {
            Image(systemName: "hand.raised")
                .font(.largeTitle)
        }
        GestureGuideItem(layout: .portrait) {
            Image(systemName: "hand.raised")
                .font(.largeTitle)
        }
    }
    .padding()
    .background(Color("Experiment/Background/Primary", bundle: .module))
}
