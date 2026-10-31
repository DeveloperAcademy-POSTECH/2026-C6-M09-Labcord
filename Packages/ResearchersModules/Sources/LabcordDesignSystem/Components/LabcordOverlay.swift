import SwiftUI

public enum LabcordOverlayStrength: Sendable {
    case `default`
    case strong

    fileprivate var token: ColorToken {
        switch self {
        case .default:
            .overlayScrim
        case .strong:
            .overlayStrong
        }
    }
}

public struct LabcordOverlay: View {
    private let strength: LabcordOverlayStrength

    public init(strength: LabcordOverlayStrength = .default) {
        self.strength = strength
    }

    public var body: some View {
        Rectangle()
            .fill(.labcord(strength.token))
            .accessibilityHidden(true)
    }
}

public struct LabcordOverlayFade: View {
    private let edge: VerticalEdge

    public init(edge: VerticalEdge = .top) {
        self.edge = edge
    }

    public var body: some View {
        ZStack {
            fade(gray: 0.4000000059604645, opacity: 0.5, blendMode: .luminosity)
            fade(gray: 0.699999988079071, blendMode: .plusDarker)
            fade(gray: 0, opacity: 0.10000000149011612, blendMode: .colorBurn)
            fade(gray: 0.4000000059604645, blendMode: .multiply)
            fade(gray: 0.501960813999176, blendMode: .colorDodge)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func fade(
        gray: Double,
        opacity: Double = 1,
        blendMode: BlendMode
    ) -> some View {
        LinearGradient(
            stops: [
                .init(color: color(gray: gray, opacity: edge == .top ? 1 : 0), location: 0),
                .init(color: color(gray: gray, opacity: edge == .top ? 0 : 1), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .opacity(opacity)
        .drawingGroup(opaque: false, colorMode: .nonLinear)
        .blendMode(blendMode)
    }

    private func color(gray: Double, opacity: Double) -> Color {
        Color(.sRGB, red: gray, green: gray, blue: gray, opacity: opacity)
    }
}
