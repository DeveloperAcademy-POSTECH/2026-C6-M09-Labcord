import LabcordDesignSystem
import SwiftUI

enum CatalogTypographyPlatform: String, CaseIterable {
    case iOS
    case watch = "Watch"

    static var current: Self {
        #if os(watchOS)
        .watch
        #else
        .iOS
        #endif
    }
}

enum CatalogWatchTypography: String, CaseIterable {
    case largeTitle = "Large Title"
    case title1 = "Title 1"
    case title2 = "Title 2"
    case title3 = "Title 3"
    case headline = "Headline"
    case body = "Body"
    case caption1 = "Caption 1"
    case caption2 = "Caption 2"
    case footnote1 = "Footnote 1"

    var pointSize: CGFloat {
        switch self {
        case .largeTitle: 36
        case .title1: 34
        case .title2: 28
        case .title3: 19
        case .headline, .body: 16
        case .caption1: 15
        case .caption2: 14
        case .footnote1: 13
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title1: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .caption1: .caption
        case .caption2: .caption2
        case .footnote1: .footnote
        }
    }

    #if os(watchOS)
    @MainActor
    var style: TypographyStyle {
        switch self {
        case .largeTitle: Typography.largeTitle
        case .title1: Typography.title1
        case .title2: Typography.title2
        case .title3: Typography.title3
        case .headline: Typography.headline
        case .body: Typography.body
        case .caption1: Typography.caption1
        case .caption2: Typography.caption2
        case .footnote1: Typography.footnote
        }
    }
    #endif
}

struct CatalogWatchTypographyPreview: View {
    let style: CatalogWatchTypography
    @ScaledMetric private var pointSize: CGFloat

    init(style: CatalogWatchTypography) {
        self.style = style
        _pointSize = ScaledMetric(wrappedValue: style.pointSize, relativeTo: style.textStyle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(style.rawValue)
                .typography(Typography.caption1)
                .foregroundStyle(.labcord(.labelSecondary))
                .fixedSize(horizontal: false, vertical: true)
            Text("실험의 흐름을 기록해요 0123456789")
                #if os(watchOS)
                .typography(style.style)
                #else
                .font(.system(size: pointSize, weight: style == .headline ? .semibold : .regular))
                #endif
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("foundation.typography.preview.watch.\(style.rawValue)")
            Text("Watch · large 기준 \(Int(style.pointSize))pt · 시스템 글꼴")
                .typography(Typography.caption1)
                .foregroundStyle(.labcord(.labelSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
