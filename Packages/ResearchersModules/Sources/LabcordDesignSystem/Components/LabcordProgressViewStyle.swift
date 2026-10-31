import SwiftUI

public struct LabcordProgressViewStyle: ProgressViewStyle {
    public enum Size: CGFloat, CaseIterable, Sendable {
        case small = 16
        case medium = 20
        case large = 24

        var points: CGFloat { rawValue }
    }

    private let size: Size
    private let foreground: Color?

    public init(
        size: Size = .small,
        foreground: Color? = nil
    ) {
        self.size = size
        self.foreground = foreground
    }

    public func makeBody(configuration: Configuration) -> some View {
        LabcordProgressContent(size: size, foreground: foreground, configuration: configuration)
    }
}

public extension ProgressViewStyle where Self == LabcordProgressViewStyle {
    static func labcord(
        size: LabcordProgressViewStyle.Size = .small,
        foreground: Color? = nil
    ) -> LabcordProgressViewStyle {
        LabcordProgressViewStyle(size: size, foreground: foreground)
    }
}

private struct LabcordProgressContent: View {
    @Environment(\.labcordTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    let size: LabcordProgressViewStyle.Size
    let foreground: Color?
    let configuration: ProgressViewStyleConfiguration

    private var resolvedForeground: Color {
        foreground ?? theme.color(.labelPrimary, colorScheme: colorScheme)
    }

    @ViewBuilder
    var body: some View {
        if configuration.fractionCompleted != nil {
            ProgressView(configuration)
                .progressViewStyle(.linear)
                .tint(resolvedForeground)
        } else if let label = configuration.label {
            HStack(spacing: LayoutTokens().spacing8) {
                LabcordLoadingIndicator(size: size, foreground: resolvedForeground)
                label
            }
            .accessibilityElement(children: .combine)
        } else {
            LabcordLoadingIndicator(size: size, foreground: resolvedForeground)
                .accessibilityElement(children: .ignore)
        }
    }
}

private struct LabcordLoadingIndicator: View {
    private let foreground: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var scaledSize: CGFloat

    init(size: LabcordProgressViewStyle.Size, foreground: Color) {
        self.foreground = foreground
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
                                .fill(foreground)
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
            .foregroundStyle(foreground)
            .frame(width: scaledSize, height: scaledSize)
            .accessibilityHidden(true)
    }
}

#Preview("진행 표시") {
    VStack(spacing: 16) {
        ProgressView()
            .progressViewStyle(.labcord(size: .small))
        ProgressView("불러오는 중")
            .progressViewStyle(.labcord(size: .medium))
        ProgressView(value: 0.6)
            .progressViewStyle(.labcord(size: .large))
    }
    .padding()
}
