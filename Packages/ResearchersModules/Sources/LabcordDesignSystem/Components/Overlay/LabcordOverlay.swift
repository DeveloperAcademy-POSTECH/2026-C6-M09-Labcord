import SwiftUI

public enum LabcordOverlayStrength: Sendable {
    case `default`
    case strong

    fileprivate var color: Color {
        switch self {
        case .default:
            Color("General/Overlay/Scrim", bundle: .module)
        case .strong:
            Color("General/Overlay/Strong", bundle: .module)
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
            .fill(strength.color)
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
            fade(color: "Gray40", opacity: 0.5, blendMode: .luminosity)
            fade(color: "Gray70", blendMode: .plusDarker)
            fade(color: "Black", opacity: 0.10000000149011612, blendMode: .colorBurn)
            fade(color: "Gray40", blendMode: .multiply)
            fade(color: "Gray50", blendMode: .colorDodge)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func fade(
        color: String,
        opacity: Double = 1,
        blendMode: BlendMode
    ) -> some View {
        LinearGradient(
            stops: [
                .init(color: fadeColor(color, isOpaque: edge == .top), location: 0),
                .init(color: fadeColor(color, isOpaque: edge == .bottom), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .opacity(opacity)
        .drawingGroup(opaque: false, colorMode: .nonLinear)
        .blendMode(blendMode)
    }

    private func fadeColor(_ name: String, isOpaque: Bool) -> Color {
        let variant = isOpaque ? "Opaque" : "Clear"
        return Color("Gradient/Fade/\(name)/\(variant)", bundle: .module)
    }
}

#Preview("오버레이") {
    HStack(spacing: 12) {
        Color.green.overlay { LabcordOverlay() }
        Color.green.overlay { LabcordOverlay(strength: .strong) }
    }
    .frame(height: 160)
    .padding()
}

#Preview("오버레이 페이드") {
    HStack(spacing: 12) {
        Color.green.overlay { LabcordOverlayFade(edge: .top) }
        Color.green.overlay { LabcordOverlayFade(edge: .bottom) }
    }
    .frame(height: 160)
    .padding()
}
