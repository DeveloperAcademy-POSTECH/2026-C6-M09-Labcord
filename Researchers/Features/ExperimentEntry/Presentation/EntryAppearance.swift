import SwiftUI

/// Figma 수치의 임시 매핑입니다. 디자인시스템 적용 시 이 파일과 표시 컴포넌트만 교체합니다.
enum EntryAppearance {
    static let background = Color.white
    static let text = Color.black
    static let secondaryText = Color(white: 0.6)
    static let separator = Color(red: 229 / 255, green: 229 / 255, blue: 234 / 255)
    static let accent = Color(red: 0, green: 136 / 255, blue: 1)
    static let addFill = Color(red: 0, green: 145 / 255, blue: 1)
    static let optionFill = Color(red: 116 / 255, green: 116 / 255, blue: 128 / 255)
        .opacity(0.08)
    static let disabledFill = Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255)
        .opacity(0.12)
    static let disabledText = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255)
        .opacity(0.3)

    static let homeInset: CGFloat = 20
    static let registrationInset: CGFloat = 16
    static let rowHeight: CGFloat = 66
    static let sectionGap: CGFloat = 64
    static let optionGap: CGFloat = 14
    static let optionRadius: CGFloat = 6

    static func label(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

struct EntryRoundButton: View {
    let symbol: String
    let title: String
    var isProminent = false
    var size: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(EntryAppearance.label(24))
                .foregroundStyle(isProminent ? .white : EntryAppearance.text)
                .frame(width: size, height: size)
                .background(
                    isProminent ? EntryAppearance.addFill : Color(white: 0.98),
                    in: Circle()
                )
                .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
