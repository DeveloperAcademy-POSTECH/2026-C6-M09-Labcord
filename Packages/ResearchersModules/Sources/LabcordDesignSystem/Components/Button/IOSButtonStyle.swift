import SwiftUI

@MainActor
public struct IOSButtonStyle: ButtonStyle {
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

    public enum ColorPalette: Sendable {
        case general, experiment
    }

    private let variant: Variant
    private let size: ComponentSize?
    private let isLoading: Bool
    private let colorPalette: ColorPalette

    public init(
        _ variant: Variant,
        size: ComponentSize? = nil,
        isLoading: Bool = false,
        colorPalette: ColorPalette = .general
    ) {
        self.variant = variant
        self.size = size
        self.isLoading = isLoading
        self.colorPalette = colorPalette
    }

    public func makeBody(configuration: Configuration) -> some View {
        ButtonContent(
            configuration: configuration,
            variant: variant,
            size: size,
            isLoading: isLoading,
            colorPalette: colorPalette
        )
    }

    private struct ButtonContent: View {
        @Environment(\.controlSize) private var controlSize
        @Environment(\.isEnabled) private var isEnabled
        @ScaledMetric(relativeTo: .body) private var cornerRadiusScale: CGFloat = 1
        @ScaledMetric(relativeTo: .body) private var extraLargeLoadingSize: CGFloat = 32

        let configuration: ButtonStyleConfiguration
        let variant: Variant
        let size: ComponentSize?
        let isLoading: Bool
        let colorPalette: ColorPalette

        private var resolvedSize: ComponentSize {
            size ?? ComponentSize(controlSize)
        }

        private var metrics: ButtonMetrics {
            ButtonMetrics(size: resolvedSize, variant: variant)
        }

        private var appearance: ButtonAppearance {
            labcordButtonAppearance(
                variant: variant,
                isDestructive: configuration.role == .destructive,
                isDisabled: !isEnabled && !isLoading,
                colorPalette: colorPalette
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
            .foregroundStyle(appearance.foreground)
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
                        .strokeBorder(border, lineWidth: 1)
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
                        ButtonLabelStyle(
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
                    .fill(background)
            } else {
                buttonShape
                    .fill(Color.clear)
            }
        }

        @ViewBuilder
        private var loadingIndicator: some View {
            if resolvedSize == .extraLarge
                && (variant == .secondary || variant == .tertiary || variant == .accent) {
                progressIndicator
                    .scaleEffect(32 / metrics.loadingIndicatorSize.points)
                    .frame(width: extraLargeLoadingSize, height: extraLargeLoadingSize)
            } else {
                progressIndicator
            }
        }

        private var progressIndicator: some View {
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

public extension ButtonStyle where Self == IOSButtonStyle {
    static func labcord(
        _ variant: IOSButtonStyle.Variant,
        size: ComponentSize? = nil,
        isLoading: Bool = false,
        colorPalette: IOSButtonStyle.ColorPalette = .general
    ) -> IOSButtonStyle {
        IOSButtonStyle(variant, size: size, isLoading: isLoading, colorPalette: colorPalette)
    }
}

struct ButtonMetrics {
    static let symbolFontPointSizeFactor: CGFloat = 1.1

    let height: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let spacing: CGFloat
    let cornerRadius: CGFloat
    let iconSize: CGFloat
    let loadingIndicatorSize: LoadingIndicatorStyle.Size
    let typography: TypographyStyle

    @MainActor
    init(size: ComponentSize, variant: IOSButtonStyle.Variant) {

        switch size {
        case .small:
            height = 32
            horizontalPadding = LayoutTokens.spacing12
            verticalPadding = 6
            spacing = LayoutTokens.spacing4
            cornerRadius = LayoutTokens.radiusFull
            iconSize = 16
            loadingIndicatorSize = .small
            typography = Typography.subheadline
        case .medium:
            height = 38
            horizontalPadding = LayoutTokens.spacing16
            verticalPadding = LayoutTokens.spacing8
            spacing = LayoutTokens.spacing8
            cornerRadius = LayoutTokens.radiusFull
            iconSize = 20
            loadingIndicatorSize = .medium
            typography = Typography.callout
        case .large:
            height = 50
            horizontalPadding = LayoutTokens.spacing24
            verticalPadding = 13
            spacing = LayoutTokens.spacing8
            cornerRadius = LayoutTokens.radiusFull
            iconSize = variant == .quaternary || variant == .accent ? 16 : 24
            loadingIndicatorSize = .large
            typography = Typography.body
        case .extraLarge:
            height = 66
            horizontalPadding = LayoutTokens.spacing32
            verticalPadding = 21
            spacing = LayoutTokens.spacing10
            cornerRadius = LayoutTokens.radiusFull
            iconSize = variant == .primary ? 24 : 32
            loadingIndicatorSize = .large
            typography = Typography.title3
        }
    }
}

private struct ButtonLabelStyle: LabelStyle {
    let spacing: CGFloat
    let iconSize: CGFloat

    @ScaledMetric(relativeTo: .body) private var dynamicTypeScale = 1

    private var scaledIconSize: CGFloat {
        iconSize * dynamicTypeScale
    }

    private var symbolFontPointSize: CGFloat {
        scaledIconSize * ButtonMetrics.symbolFontPointSizeFactor
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

struct ButtonAppearance {
    let background: Color?
    let foreground: Color
    let border: Color?
}

func labcordButtonAppearance(
    variant: IOSButtonStyle.Variant,
    isDestructive: Bool,
    isDisabled: Bool,
    colorPalette: IOSButtonStyle.ColorPalette = .general
) -> ButtonAppearance {
    let resolve: (ColorResource, ColorResource) -> Color = {
        Color(colorPalette == .general ? $0 : $1)
    }

    if isDisabled {
        return ButtonAppearance(
            background: variant == .quaternary || variant == .accent
                ? nil : resolve(
                    .General.Action.Disabled.background,
                    .Experiment.Action.Disabled.background
                ),
            foreground: resolve(
                .General.Action.Disabled.foreground,
                .Experiment.Action.Disabled.foreground
            ),
            border: nil
        )
    }

    let subtleBackground = resolve(
        .General.Action.Destructive.subtleBackground,
        .Experiment.Action.Destructive.subtleBackground
    )
    let subtleForeground = resolve(
        .General.Action.Destructive.subtleForeground,
        .Experiment.Action.Destructive.subtleForeground
    )
    let secondaryLabel = resolve(.General.Label.secondary, .Experiment.Label.secondary)
    switch variant {
    case .primary, .secondary:
        return prominentButtonAppearance(
            variant: variant, isDestructive: isDestructive, resolve: resolve
        )
    case .tertiary:
        return ButtonAppearance(
            background: isDestructive
                ? subtleBackground : resolve(.General.Fill.secondary, .Experiment.Fill.secondary),
            foreground: isDestructive ? subtleForeground : secondaryLabel,
            border: nil
        )
    case .quaternary, .accent:
        let normal = variant == .accent
            ? resolve(.General.Label.brand, .Experiment.Label.brand) : secondaryLabel
        return ButtonAppearance(
            background: nil,
            foreground: isDestructive ? subtleForeground : normal,
            border: nil
        )
    }
}

private func prominentButtonAppearance(
    variant: IOSButtonStyle.Variant,
    isDestructive: Bool,
    resolve: (ColorResource, ColorResource) -> Color
) -> ButtonAppearance {
    let destructiveBackground = resolve(
        .General.Action.Destructive.background,
        .Experiment.Action.Destructive.background
    )
    if variant == .primary {
        return ButtonAppearance(
            background: isDestructive ? destructiveBackground : resolve(
                .General.Action.Primary.background, .Experiment.Action.Primary.background
            ),
            foreground: isDestructive ? resolve(
                .General.Action.Destructive.foreground, .Experiment.Action.Destructive.foreground
            ) : resolve(.General.Label.inverse, .Experiment.Label.inverse),
            border: isDestructive ? destructiveBackground : nil
        )
    }
    return ButtonAppearance(
        background: isDestructive ? resolve(
            .General.Action.Destructive.subtleBackground,
            .Experiment.Action.Destructive.subtleBackground
        ) : resolve(.General.Action.Secondary.background, .Experiment.Action.Secondary.background),
        foreground: isDestructive ? resolve(
            .General.Action.Destructive.subtleForeground,
            .Experiment.Action.Destructive.subtleForeground
        ) : resolve(.General.Action.Secondary.foreground, .Experiment.Action.Secondary.foreground),
        border: nil
    )
}

#Preview("버튼") {
    _ = FontRegistration.register()
    return VStack(spacing: 12) {
        Button("기본") { }
            .buttonStyle(.labcord(.primary))
        Button("보조") { }
            .buttonStyle(.labcord(.secondary))
        Button("비활성화") { }
            .buttonStyle(.labcord(.tertiary))
            .disabled(true)
        Button("삭제", role: .destructive) { }
            .buttonStyle(.labcord(.primary))
        Button("불러오는 중") { }
            .buttonStyle(.labcord(.primary, isLoading: true))
        Button("아주 큰 버튼", systemImage: "plus") { }
            .buttonStyle(.labcord(.primary, size: .extraLarge))
    }
    .padding()
}
