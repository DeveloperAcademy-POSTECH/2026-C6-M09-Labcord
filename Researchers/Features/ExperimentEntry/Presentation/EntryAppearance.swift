import CoreText
import Foundation
import SwiftUI

/// Figma 수치의 임시 매핑입니다. 디자인시스템 적용 시 이 파일과 표시 컴포넌트만 교체합니다.
enum EntryAppearance {
    static let background = Color.white
    static let text = Color.black
    static let secondaryText = Color(white: 158 / 255)
    static let separator = Color(red: 229 / 255, green: 229 / 255, blue: 234 / 255)
    static let accent = Color(red: 0, green: 136 / 255, blue: 1)
    static let addFill = Color(red: 0, green: 145 / 255, blue: 1)
    static let symbol = Color(white: 26 / 255)
    static let neutralSurface = LinearGradient(
        colors: [Color(white: 238 / 255), Color(white: 254 / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let secondarySymbol = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255)
        .opacity(0.6)
    static let optionFill = Color(red: 116 / 255, green: 116 / 255, blue: 128 / 255)
        .opacity(0.08)
    static let disabledFill = Color(red: 238 / 255, green: 238 / 255, blue: 239 / 255)
    static let disabledText = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255)
        .opacity(0.3)

    static let homeInset: CGFloat = 20
    static let registrationInset: CGFloat = 16
    static let rowHeight: CGFloat = 66
    static let sectionGap: CGFloat = 46
    static let optionGap: CGFloat = 14
    static let optionRadius: CGFloat = 6

    static func label(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func labelText(_ value: String, style: EntryText.Style) -> Text {
        let registered = registeredFonts
        var content = AttributedString(value)
        content.font = label(style.size, weight: style == .headline ? .semibold : .regular)
        for index in content.characters.indices {
            let character = content.characters[index]
            let end = content.characters.index(after: index)
            if containsHangul(String(character)), registered {
                let name = style == .headline ? "Medium" : "Regular"
                content[index..<end].font = .custom(
                    "LabcordEntryHangul-\(name)", fixedSize: style.size
                )
                content[index..<end].tracking = style.tracking
            }
        }
        return Text(content)
    }

    static func containsHangul(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F,
                 0xAC00...0xD7A3, 0xD7B0...0xD7FF, 0xFFA0...0xFFDC:
                true
            default:
                false
            }
        }
    }

    static func baselineOffset(_ value: String, style: EntryText.Style) -> CGFloat {
        registeredFonts && containsHangul(value) ? style.baselineOffset : 0
    }

    private static let registeredFonts: Bool = {
        for style in ["Regular", "Medium"] {
            guard let url = Bundle.main.url(
                forResource: "LabcordEntryHangul-\(style)", withExtension: "ttf"
            ), CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) else {
                return false
            }
        }
        return true
    }()
}

struct EntryRoundButton: View {
    let symbol: String
    let title: String
    var isProminent = false
    var size: CGFloat = 48
    var symbolSize: CGFloat = 24
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            symbolImage
                .foregroundStyle(isProminent ? .white : EntryAppearance.symbol)
                .blendMode(isProminent ? .plusLighter : .plusDarker)
                .frame(width: size, height: size)
                .background(
                    isProminent
                        ? AnyShapeStyle(EntryAppearance.addFill)
                        : AnyShapeStyle(EntryAppearance.neutralSurface),
                    in: Circle()
                )
                .compositingGroup()
                .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var symbolImage: some View {
        switch symbol {
        case "gear":
            asset("EntryGear", width: 25, height: 25, x: 0.1484375, y: 0.16357421875)
        case "plus":
            asset("EntryPlus", width: 18, height: 18, x: 0.134765625, y: 0.1416015625)
        case "chevron.backward":
            asset("EntryBack", width: 11, height: 19, x: -1.20703125, y: 0.2431640625)
        default:
            Image(systemName: symbol).font(EntryAppearance.label(symbolSize))
        }
    }

    private func asset(
        _ name: String, width: CGFloat, height: CGFloat, x offsetX: CGFloat, y offsetY: CGFloat
    ) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .frame(width: width, height: height)
            .offset(x: offsetX, y: offsetY)
    }
}

/// 비활성 색상은 Figma 값을 사용하고 기본 스타일의 이중 흐림을 방지합니다.
struct EntryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}
