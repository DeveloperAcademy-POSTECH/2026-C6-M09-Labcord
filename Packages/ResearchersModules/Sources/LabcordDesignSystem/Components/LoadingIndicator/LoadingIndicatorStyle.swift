import SwiftUI

public struct LoadingIndicatorStyle: ProgressViewStyle {
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
        ProgressContent(size: size, foreground: foreground, configuration: configuration)
    }
}

public extension ProgressViewStyle where Self == LoadingIndicatorStyle {
    static func labcord(
        size: LoadingIndicatorStyle.Size = .small,
        foreground: Color? = nil
    ) -> LoadingIndicatorStyle {
        LoadingIndicatorStyle(size: size, foreground: foreground)
    }
}

private struct ProgressContent: View {
    let size: LoadingIndicatorStyle.Size
    let foreground: Color?
    let configuration: ProgressViewStyleConfiguration

    private var resolvedForeground: Color {
        foreground ?? Color(.General.Label.primary)
    }

    private var inactiveForeground: Color {
        foreground ?? Color(.General.Label.tertiary)
    }

    @ViewBuilder
    var body: some View {
        if configuration.fractionCompleted != nil {
            ProgressView(configuration)
                .progressViewStyle(.linear)
                .tint(foreground ?? Color(.General.Label.primary))
        } else if let label = configuration.label {
            HStack(spacing: LayoutTokens.spacing8) {
                LoadingIndicator(
                    size: size,
                    foreground: resolvedForeground,
                    inactiveForeground: inactiveForeground
                )
                label
            }
            .accessibilityElement(children: .combine)
        } else {
            LoadingIndicator(
                size: size, foreground: resolvedForeground, inactiveForeground: inactiveForeground
            )
                .accessibilityElement(children: .ignore)
        }
    }
}

private struct LoadingIndicator: View {
    private let size: LoadingIndicatorStyle.Size
    private let foreground: Color
    private let inactiveForeground: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var scaledSize: CGFloat

    init(size: LoadingIndicatorStyle.Size, foreground: Color, inactiveForeground: Color) {
        self.size = size
        self.foreground = foreground
        self.inactiveForeground = inactiveForeground
        _scaledSize = ScaledMetric(wrappedValue: size.points, relativeTo: .body)
    }

    var body: some View {
        Group {
            if reduceMotion {
                dots(activeDot: 0)
                    .accessibilityHidden(true)
            } else {
                PhaseAnimator([0, 1, 2]) { activeDot in
                    dots(activeDot: activeDot)
                } animation: { _ in
                    .linear(duration: 0.45)
                }
                .accessibilityHidden(true)
            }
        }
        .frame(width: scaledSize, height: scaledSize)
    }

    private var activeDotSize: CGFloat {
        let points: CGFloat
        switch size {
        case .small: points = 5
        case .medium: points = 6
        case .large: points = 7
        }
        return points * scaledSize / size.points
    }

    private var inactiveDotSize: CGFloat {
        let points: CGFloat
        switch size {
        case .small: points = 3
        case .medium: points = 4
        case .large: points = 5
        }
        return points * scaledSize / size.points
    }

    private func dots(activeDot: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<3) { dot in
                Circle()
                    .fill(activeDot == dot ? foreground : inactiveForeground)
                    .frame(width: inactiveDotSize, height: inactiveDotSize)
                    .scaleEffect(activeDot == dot ? activeDotSize / inactiveDotSize : 1)
                    .frame(width: activeDotSize, height: activeDotSize)
            }
        }
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
    .foregroundStyle(.white)
    .background(Color(.Experiment.Background.primary))
}
