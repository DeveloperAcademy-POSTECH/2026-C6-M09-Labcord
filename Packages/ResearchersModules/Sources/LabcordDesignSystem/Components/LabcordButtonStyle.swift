import SwiftUI

@MainActor
public struct LabcordButtonStyle: ButtonStyle {
    public enum Variant: String, CaseIterable, Sendable {
        case primary
        case secondary
        case tertiary
        case quaternary
        case accent

        public static var filled: Self { .primary }
        public static var tinted: Self { .secondary }
        public static var neutral: Self { .tertiary }
        public static var plain: Self { .quaternary }
    }

    private let variant: Variant
    private let size: LabcordControlSize?
    private let isLoading: Bool

    public init(
        _ variant: Variant,
        size: LabcordControlSize? = nil,
        isLoading: Bool = false
    ) {
        self.variant = variant
        self.size = size
        self.isLoading = isLoading
    }

    public func makeBody(configuration: Configuration) -> some View {
        ButtonContent(
            configuration: configuration,
            variant: variant,
            size: size,
            isLoading: isLoading
        )
    }

    private struct ButtonContent: View {
        @Environment(\.controlSize) private var controlSize
        @Environment(\.isEnabled) private var isEnabled
        @ScaledMetric(relativeTo: .body) private var cornerRadiusScale: CGFloat = 1

        let configuration: ButtonStyleConfiguration
        let variant: Variant
        let size: LabcordControlSize?
        let isLoading: Bool

        private var resolvedSize: LabcordControlSize {
            size ?? LabcordControlSize(controlSize)
        }

        private var metrics: LabcordButtonMetrics {
            LabcordButtonMetrics(size: resolvedSize, variant: variant)
        }

        private var appearance: LabcordButtonAppearance {
            labcordButtonAppearance(
                variant: variant,
                isDestructive: configuration.role == .destructive,
                isDisabled: !isEnabled && !isLoading
            )
        }

        private var isPressed: Bool {
            configuration.isPressed && isEnabled && !isLoading
        }

        private var buttonShape: RoundedRectangle {
            RoundedRectangle(
                cornerRadius: min(metrics.cornerRadius, metrics.height / 2 * cornerRadiusScale),
                style: .continuous
            )
        }

        private var horizontalPadding: CGFloat {
            let borderPadding: CGFloat = appearance.border != nil && !isLoading ? 1 : 0
            return metrics.horizontalPadding + borderPadding
        }

        @ViewBuilder
        var body: some View {
            if isLoading {
                styledContent
                    .accessibilityRepresentation {
                        configuration.label
                    }
            } else {
                styledContent
            }
        }

        private var styledContent: some View {
            buttonContent
            .typography(metrics.typography)
            .foregroundStyle(LabcordColor(appearance.foreground))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, isLoading ? 0 : metrics.verticalPadding)
            .frame(minHeight: metrics.height)
            .background {
                backgroundView
            }
            .clipShape(buttonShape)
            .overlay {
                if let border = appearance.border {
                    buttonShape
                        .strokeBorder(LabcordColor(border), lineWidth: 1)
                }
            }
            .contentShape(buttonShape)
            .labcordPressFeedback(isPressed)
        }
        @ViewBuilder
        private var buttonContent: some View {
            if isLoading {
                loadingIndicator
            } else {
                configuration.label
                    .labelStyle(
                        LabcordButtonLabelStyle(
                            spacing: metrics.spacing,
                            iconSize: metrics.iconSize
                        )
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        @ViewBuilder
        private var backgroundView: some View {
            if let background = appearance.background {
                buttonShape
                    .fill(LabcordColor(background))
            } else {
                buttonShape
                    .fill(Color.clear)
            }
        }

        private var loadingIndicator: some View {
            ProgressView()
                .progressViewStyle(
                    .labcord(
                        size: metrics.loadingIndicatorSize,
                        foreground: appearance.foreground
                    )
                )
                .accessibilityHidden(true)
        }

    }
}

public extension ButtonStyle where Self == LabcordButtonStyle {
    static func labcord(
        _ variant: LabcordButtonStyle.Variant,
        size: LabcordControlSize? = nil,
        isLoading: Bool = false
    ) -> LabcordButtonStyle {
        LabcordButtonStyle(variant, size: size, isLoading: isLoading)
    }
}

struct LabcordButtonMetrics {
    static let symbolFontPointSizeFactor: CGFloat = 1.1

    let height: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let spacing: CGFloat
    let cornerRadius: CGFloat
    let iconSize: CGFloat
    let loadingIndicatorSize: LabcordProgressViewStyle.Size
    let typography: TypographyStyle

    @MainActor
    init(size: LabcordControlSize, variant: LabcordButtonStyle.Variant) {
        let layout = LayoutTokens()

        switch size {
        case .small:
            height = 32
            horizontalPadding = layout.spacing12
            verticalPadding = 6
            spacing = layout.spacing4
            cornerRadius = layout.radiusFull
            iconSize = 16
            loadingIndicatorSize = .small
            typography = Typography.subheadline
        case .medium:
            height = 38
            horizontalPadding = layout.spacing16
            verticalPadding = layout.spacing8
            spacing = layout.spacing8
            cornerRadius = layout.radiusFull
            iconSize = 20
            loadingIndicatorSize = .medium
            typography = Typography.callout
        case .large:
            height = 50
            horizontalPadding = layout.spacing24
            verticalPadding = 13
            spacing = layout.spacing8
            cornerRadius = layout.radiusFull
            iconSize = variant == .quaternary || variant == .accent ? 16 : 24
            loadingIndicatorSize = .large
            typography = Typography.body
        }
    }
}

private struct LabcordButtonLabelStyle: LabelStyle {
    let spacing: CGFloat
    let iconSize: CGFloat

    @ScaledMetric(relativeTo: .body) private var dynamicTypeScale = 1

    private var scaledIconSize: CGFloat {
        iconSize * dynamicTypeScale
    }

    private var symbolFontPointSize: CGFloat {
        scaledIconSize * LabcordButtonMetrics.symbolFontPointSizeFactor
    }

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
                .font(.system(size: symbolFontPointSize))
                .imageScale(.large)
                .frame(width: scaledIconSize, height: scaledIconSize)
            configuration.title
        }
    }
}

struct LabcordButtonAppearance {
    let background: ColorToken?
    let foreground: ColorToken
    let border: ColorToken?
}

func labcordButtonAppearance(
    variant: LabcordButtonStyle.Variant,
    isDestructive: Bool,
    isDisabled: Bool
) -> LabcordButtonAppearance {
    if isDisabled {
        return LabcordButtonAppearance(
            background: variant == .quaternary || variant == .accent
                ? nil : .actionDisabledBackground,
            foreground: .actionDisabledForeground,
            border: nil
        )
    }

    switch variant {
    case .primary:
        return LabcordButtonAppearance(
            background: isDestructive ? .actionDestructiveBackground : .actionPrimaryBackground,
            foreground: isDestructive ? .actionDestructiveForeground : .labelInverse,
            border: isDestructive ? .actionDestructiveBackground : nil
        )
    case .secondary:
        return LabcordButtonAppearance(
            background: isDestructive
                ? .actionDestructiveSubtleBackground
                : .actionSecondaryBackground,
            foreground: isDestructive
                ? .actionDestructiveSubtleForeground
                : .actionSecondaryForeground,
            border: nil
        )
    case .tertiary:
        return LabcordButtonAppearance(
            background: isDestructive ? .actionDestructiveSubtleBackground : .fillSecondary,
            foreground: isDestructive ? .actionDestructiveSubtleForeground : .labelSecondary,
            border: nil
        )
    case .quaternary:
        return LabcordButtonAppearance(
            background: nil,
            foreground: isDestructive ? .actionDestructiveSubtleForeground : .labelSecondary,
            border: nil
        )
    case .accent:
        return LabcordButtonAppearance(
            background: nil,
            foreground: isDestructive ? .actionDestructiveSubtleForeground : .labelBrand,
            border: nil
        )
    }
}
