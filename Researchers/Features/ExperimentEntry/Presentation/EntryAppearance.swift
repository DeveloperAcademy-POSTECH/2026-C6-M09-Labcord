import SwiftUI

/// 화면의 기본 색상과 배치 간격입니다.
enum EntryAppearance {
    static let background = Color(.systemBackground)
    static let text = Color.primary
    static let secondaryText = Color.secondary
    static let separator = Color.secondary.opacity(0.2)
    static let accent = Color.accentColor
    static let symbol = Color.primary
    static let neutralSurface = Color(.secondarySystemBackground)
    static let secondarySymbol = Color.secondary
    static let optionFill = Color(.secondarySystemBackground)
    static let disabledFill = Color(.secondarySystemBackground)
    static let disabledText = Color.secondary

    static let homeInset: CGFloat = 20
    static let registrationInset: CGFloat = 16
    static let rowHeight: CGFloat = 66
    static let sectionGap: CGFloat = 46
    static let optionGap: CGFloat = 14
    static let optionRadius: CGFloat = 6
}

struct EntryRoundButton: View {
    let imageName: String
    let title: String
    var isProminent = false
    var size: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(imageName)
                .renderingMode(.template)
                .resizable()
                .interpolation(.none)
                .foregroundStyle(isProminent ? .white : EntryAppearance.symbol)
                .frame(width: size, height: size)
                .background(
                    isProminent ? EntryAppearance.accent : EntryAppearance.neutralSurface,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
