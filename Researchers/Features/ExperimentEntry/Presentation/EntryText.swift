import SwiftUI

/// 원본의 한글 폴백과 행 베이스라인을 표시 계층에 한정합니다.
struct EntryText: View {
    enum Style {
        case headline
        case body
        case subheadline
        case footnote
        case caption
        case title

        var size: CGFloat {
            switch self {
            case .headline, .body: 17
            case .subheadline: 15
            case .footnote: 13
            case .caption: 12
            case .title: 20
            }
        }

        var lineHeight: CGFloat {
            switch self {
            case .headline, .body: 22
            case .subheadline: 20
            case .footnote: 18
            case .caption: 16
            case .title: 25
            }
        }

        var tracking: CGFloat {
            switch self {
            case .headline, .body: -0.43
            case .subheadline: -0.23
            case .footnote: -0.08
            case .caption: 0
            case .title: -0.45
            }
        }

        // Noto 중앙 베이스라인을 Figma의 SF Pro 행 베이스라인에 맞춥니다.
        var baselineOffset: CGFloat {
            switch self {
            case .headline: -1.412
            case .body: -1.412 - 1 / 3
            case .subheadline: -1.540 + 1 / 3
            case .footnote: -0.668 + 1 / 3
            case .caption: -1.232
            case .title: -1.220
            }
        }
    }

    let value: String
    let style: Style

    init(_ value: String, style: Style) {
        self.value = value
        self.style = style
    }

    var body: some View {
        EntryAppearance.labelText(value, style: style)
            .frame(height: style.lineHeight)
            .offset(y: EntryAppearance.baselineOffset(value, style: style))
    }
}
