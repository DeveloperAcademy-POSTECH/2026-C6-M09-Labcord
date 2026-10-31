import SwiftUI

@MainActor
public struct LabcordIconButtonStyle: ButtonStyle {
    public typealias Variant = LabcordButtonStyle.Variant

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
        IconButtonContent(
            configuration: configuration,
            variant: variant,
            size: size,
            isLoading: isLoading
        )
    }

    private struct IconButtonContent: View {
        @Environment(\.controlSize) private var controlSize
        @Environment(\.isEnabled) private var isEnabled

        @ScaledMetric(relativeTo: .body) private var dynamicTypeScale = 1

        let configuration: ButtonStyleConfiguration
        let variant: Variant
        let size: LabcordControlSize?
        let isLoading: Bool

        private var resolvedSize: LabcordControlSize {
            size ?? LabcordControlSize(controlSize)
        }

        private var metrics: LabcordIconButtonMetrics {
            LabcordIconButtonMetrics(size: resolvedSize)
        }

        private var appearance: LabcordButtonAppearance {
            labcordButtonAppearance(
                variant: variant,
                isDestructive: configuration.role == .destructive,
                isDisabled: !isEnabled && !isLoading
            )
        }

        private var scaledContainerSize: CGFloat {
            metrics.containerSize * dynamicTypeScale
        }

        private var scaledIconSize: CGFloat {
            metrics.iconSize * dynamicTypeScale
        }

        private var symbolFontPointSize: CGFloat {
            scaledIconSize * LabcordButtonMetrics.symbolFontPointSizeFactor
        }

        private var isPressed: Bool {
            configuration.isPressed && isEnabled && !isLoading
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
            ZStack {
                if isLoading {
                    loadingIndicator
                } else {
                    configuration.label
                        .font(.system(size: symbolFontPointSize))
                        .imageScale(.large)
                        .frame(minWidth: scaledIconSize, minHeight: scaledIconSize)
                }
            }
            .frame(minWidth: scaledContainerSize, minHeight: scaledContainerSize)
            .foregroundStyle(LabcordColor(appearance.foreground))
            .background {
                backgroundView
            }
            .clipShape(Circle())
            .overlay {
                if let border = appearance.border {
                    Circle()
                        .strokeBorder(LabcordColor(border), lineWidth: 1)
                }
            }
            .contentShape(Circle())
            .labcordPressFeedback(isPressed)
        }

        @ViewBuilder
        private var backgroundView: some View {
            if let background = appearance.background {
                Circle()
                    .fill(LabcordColor(background))
            } else {
                Circle()
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
                .scaleEffect(metrics.loadingSlotSize / metrics.loadingIndicatorSize.points)
                .frame(
                    width: metrics.loadingSlotSize * dynamicTypeScale,
                    height: metrics.loadingSlotSize * dynamicTypeScale
                )
                .accessibilityHidden(true)
        }
    }
}

public extension ButtonStyle where Self == LabcordIconButtonStyle {
    static func labcordIcon(
        _ variant: LabcordIconButtonStyle.Variant,
        size: LabcordControlSize? = nil,
        isLoading: Bool = false
    ) -> LabcordIconButtonStyle {
        LabcordIconButtonStyle(variant, size: size, isLoading: isLoading)
    }
}

struct LabcordIconButtonMetrics {
    let containerSize: CGFloat
    let iconSize: CGFloat
    let loadingIndicatorSize: LabcordProgressViewStyle.Size
    let loadingSlotSize: CGFloat

    init(size: LabcordControlSize) {
        switch size {
        case .small:
            containerSize = 28
            iconSize = 12
            loadingIndicatorSize = .small
            loadingSlotSize = 12
        case .medium:
            containerSize = 34
            iconSize = 16
            loadingIndicatorSize = .medium
            loadingSlotSize = 16
        case .large:
            containerSize = 50
            iconSize = 24
            loadingIndicatorSize = .large
            loadingSlotSize = 24
        }
    }
}
