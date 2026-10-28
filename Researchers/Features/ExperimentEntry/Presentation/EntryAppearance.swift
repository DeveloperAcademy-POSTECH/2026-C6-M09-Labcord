import Foundation
import SwiftUI

/// Figma 수치의 임시 매핑입니다. 디자인시스템 적용 시 이 파일과 표시 컴포넌트만 교체합니다.
enum EntryAppearance {
    static let background = Color.white
    static let text = Color.black
    static let secondaryText = Color(white: 158 / 255)
    static let separator = Color(red: 229 / 255, green: 229 / 255, blue: 234 / 255)
    static let accent = Color(red: 0, green: 136 / 255, blue: 1)
    static let addFill = AnyShapeStyle(LinearGradient.linearGradient(
        Gradient(colors: [
            Color(red: 0, green: 138 / 255, blue: 248 / 255),
            Color(red: 0, green: 144 / 255, blue: 254 / 255),
            Color(red: 6 / 255, green: 150 / 255, blue: 254 / 255)
        ]).colorSpace(.device),
        startPoint: .topLeading, endPoint: .bottomTrailing
    ))
    static let addRim = AngularGradient(
        stops: stride(from: 0.0, through: 360.0, by: 22.5).map { angle in
            let light = cos((angle - 45) * .pi / 180)
            let intensity = light >= 0 ? 0.43 : 0.63
            return Gradient.Stop(
                color: .white.opacity(light * light * intensity), location: angle / 360
            )
        },
        center: .center
    )
    static let neutralRim = AngularGradient(
        stops: stride(from: 0.0, through: 360.0, by: 22.5).map { angle in
            let light = cos((angle - 45) * .pi / 180)
            let intensity = light >= 0 ? 0.05 : 0.095
            return Gradient.Stop(
                color: .white.opacity(light * light * intensity), location: angle / 360
            )
        },
        center: .center
    )
    static let symbol = Color(white: 17 / 255)
    static let neutralSurface = LinearGradient(
        colors: [Color(white: 238 / 255), Color(white: 254 / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let secondarySymbol = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255)
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
                    isProminent
                        ? AnyShapeStyle(EntryAppearance.addFill)
                        : AnyShapeStyle(EntryAppearance.neutralSurface),
                    in: Circle()
                )
                .compositingGroup()
                .shadow(color: .black.opacity(0.12), radius: 17, x: 0, y: 8)
                .overlay {
                    Circle()
                        .strokeBorder(
                            isProminent ? EntryAppearance.addRim : EntryAppearance.neutralRim,
                            lineWidth: isProminent ? 0.6 : 0.8
                        )
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// 비활성 색상은 Figma 값을 사용하고 기본 스타일의 이중 흐림을 방지합니다.
struct EntryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}
