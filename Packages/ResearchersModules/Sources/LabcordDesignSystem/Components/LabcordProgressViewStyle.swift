import SwiftUI

public struct LabcordProgressViewStyle: ProgressViewStyle {
    public enum Size: CGFloat, CaseIterable, Sendable {
        case small = 16
        case medium = 20
        case large = 24

        var points: CGFloat { rawValue }
    }

    private let size: Size
    private let foregroundToken: ColorToken

    public init(
        size: Size = .small,
        foreground: ColorToken = .labelPrimary
    ) {
        self.size = size
        foregroundToken = foreground
    }

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if configuration.fractionCompleted != nil {
            ProgressView(configuration)
                .progressViewStyle(.linear)
                .tint(LabcordColor(foregroundToken))
        } else if let label = configuration.label {
            HStack(spacing: LayoutTokens().spacing8) {
                LabcordLoadingIndicator(size: size, foregroundToken: foregroundToken)
                label
            }
            .accessibilityElement(children: .combine)
        } else {
            LabcordLoadingIndicator(size: size, foregroundToken: foregroundToken)
                .accessibilityElement(children: .ignore)
        }
    }
}

public extension ProgressViewStyle where Self == LabcordProgressViewStyle {
    static func labcord(
        size: LabcordProgressViewStyle.Size = .small,
        foreground: ColorToken = .labelPrimary
    ) -> LabcordProgressViewStyle {
        LabcordProgressViewStyle(size: size, foreground: foreground)
    }
}

private struct LabcordLoadingIndicator: View {
    private let foregroundToken: ColorToken
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var scaledSize: CGFloat

    init(size: LabcordProgressViewStyle.Size, foregroundToken: ColorToken) {
        self.foregroundToken = foregroundToken
        _scaledSize = ScaledMetric(wrappedValue: size.points, relativeTo: .body)
    }

    var body: some View {
        Group {
            if reduceMotion {
                phaseImage(1)
            } else {
                PhaseAnimator([0, 1, 2]) { activeDot in
                    HStack(spacing: 0) {
                        ForEach(0..<3) { dot in
                            Circle()
                                .fill(.labcord(foregroundToken))
                                .frame(width: scaledSize * 3 / 16, height: scaledSize * 3 / 16)
                                .scaleEffect(activeDot == dot ? 5.0 / 3 : 1)
                                .frame(width: scaledSize * 5 / 16, height: scaledSize * 5 / 16)
                        }
                    }
                } animation: { _ in
                    .linear(duration: 0.45)
                }
                .accessibilityHidden(true)
            }
        }
        .frame(width: scaledSize, height: scaledSize)
    }

    private func phaseImage(_ phase: Int) -> some View {
        Image("labcord-loading-phase\(phase)", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .foregroundStyle(.labcord(foregroundToken))
            .frame(width: scaledSize, height: scaledSize)
            .accessibilityHidden(true)
    }
}
