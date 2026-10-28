import SwiftUI

/// 시스템 기본 폰트의 크기·굵기·행높이를 표시 계층에 한정합니다.
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
    }

    let value: String
    let style: Style

    init(_ value: String, style: Style) {
        self.value = value
        self.style = style
    }

    var body: some View {
        Text(value)
            .font(EntryAppearance.label(
                style.size, weight: style == .headline ? .semibold : .regular
            ))
            .frame(height: style.lineHeight)
    }
}
