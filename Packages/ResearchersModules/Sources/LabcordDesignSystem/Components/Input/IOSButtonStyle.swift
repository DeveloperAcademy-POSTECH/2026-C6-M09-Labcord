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

    private let variant: Variant
    private let size: ComponentSize?
    private let isLoading: Bool

    public init(
        _ variant: Variant,
        size: ComponentSize? = nil,
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
        let size: ComponentSize?
        let isLoading: Bool

        private var resolvedSize: ComponentSize {
            size ?? ComponentSize(controlSize)
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
                    .fill(background)
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

public extension ButtonStyle where Self == IOSButtonStyle {
    static func labcord(
        _ variant: IOSButtonStyle.Variant,
        size: ComponentSize? = nil,
        isLoading: Bool = false
    ) -> IOSButtonStyle {
        IOSButtonStyle(variant, size: size, isLoading: isLoading)
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
    let loadingIndicatorSize: LoadingIndicatorStyle.Size
    let typography: TypographyStyle

    @MainActor
    init(size: ComponentSize, variant: IOSButtonStyle.Variant) {
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
    let background: Color?
    let foreground: Color
    let border: Color?
}

func labcordButtonAppearance(
    variant: IOSButtonStyle.Variant,
    isDestructive: Bool,
    isDisabled: Bool
) -> LabcordButtonAppearance {
    if isDisabled {
        return LabcordButtonAppearance(
            background: variant == .quaternary || variant == .accent
                ? nil : Color("General/Action/Disabled/Background", bundle: .module),
            foreground: Color("General/Action/Disabled/Foreground", bundle: .module),
            border: nil
        )
    }

    let subtleBackground = Color("General/Action/Destructive/Subtle Background", bundle: .module)
    let subtleForeground = Color("General/Action/Destructive/Subtle Foreground", bundle: .module)
    let secondaryLabel = Color("General/Label/Secondary", bundle: .module)
    switch variant {
    case .primary:
        return LabcordButtonAppearance(
            background: isDestructive
                ? Color("General/Action/Destructive/Background", bundle: .module)
                : Color("General/Action/Primary/Background", bundle: .module),
            foreground: isDestructive
                ? Color("General/Action/Destructive/Foreground", bundle: .module)
                : Color("General/Label/Inverse", bundle: .module),
            border: isDestructive
                ? Color("General/Action/Destructive/Background", bundle: .module)
                : nil
        )
    case .secondary:
        return LabcordButtonAppearance(
            background: isDestructive
                ? subtleBackground : Color("General/Action/Secondary/Background", bundle: .module),
            foreground: isDestructive
                ? subtleForeground : Color("General/Action/Secondary/Foreground", bundle: .module),
            border: nil
        )
    case .tertiary:
        return LabcordButtonAppearance(
            background: isDestructive
                ? subtleBackground : Color("General/Fill/Secondary", bundle: .module),
            foreground: isDestructive ? subtleForeground : secondaryLabel,
            border: nil
        )
    case .quaternary, .accent:
        let normal = variant == .accent
            ? Color("General/Label/Brand", bundle: .module) : secondaryLabel
        return LabcordButtonAppearance(
            background: nil,
            foreground: isDestructive ? subtleForeground : normal,
            border: nil
        )
    }
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
    }
    .padding()
}

public typealias LabcordButtonStyle = IOSButtonStyle
