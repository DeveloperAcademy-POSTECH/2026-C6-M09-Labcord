import SwiftUI

@MainActor
public struct IOSIconButtonStyle: ButtonStyle {
    public typealias Variant = IOSButtonStyle.Variant

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
        let size: ComponentSize?
        let isLoading: Bool

        private var resolvedSize: ComponentSize {
            size ?? ComponentSize(controlSize)
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
                    LabcordIconArtwork(icon: .dotsThreeOutline, size: metrics.iconSize)
                } else {
                    configuration.label
                        .font(.system(size: symbolFontPointSize))
                        .imageScale(.large)
                        .frame(minWidth: scaledIconSize, minHeight: scaledIconSize)
                }
            }
            .frame(minWidth: scaledContainerSize, minHeight: scaledContainerSize)
            .foregroundStyle(appearance.foreground)
            .background {
                backgroundView
            }
            .clipShape(Circle())
            .overlay {
                if let border = appearance.border {
                    Circle()
                        .strokeBorder(border, lineWidth: 1)
                }
            }
            .contentShape(Circle())
            .labcordPressFeedback(isPressed)
            .allowsHitTesting(!isLoading)
            .disabled(isLoading)
        }

        @ViewBuilder
        private var backgroundView: some View {
            if let background = appearance.background {
                Circle()
                    .fill(background)
            } else {
                Circle()
                    .fill(Color.clear)
            }
        }

    }
}

public extension ButtonStyle where Self == IOSIconButtonStyle {
    static func labcordIcon(
        _ variant: IOSIconButtonStyle.Variant,
        size: ComponentSize? = nil,
        isLoading: Bool = false
    ) -> IOSIconButtonStyle {
        IOSIconButtonStyle(variant, size: size, isLoading: isLoading)
    }
}

struct LabcordIconButtonMetrics {
    let containerSize: CGFloat
    let iconSize: CGFloat

    init(size: ComponentSize) {
        switch size {
        case .small:
            containerSize = 28
            iconSize = 12
        case .medium:
            containerSize = 34
            iconSize = 16
        case .large:
            containerSize = 50
            iconSize = 24
        case .extraLarge:
            containerSize = 66
            iconSize = 34
        }
    }
}

#Preview("아이콘 버튼") {
    HStack(spacing: 12) {
        Button { } label: {
            LabcordIconArtwork(icon: .plus, size: 20)
        }
        .buttonStyle(.labcordIcon(.primary))
        Button { } label: {
            LabcordIconArtwork(icon: .trash, size: 20)
        }
        .buttonStyle(.labcordIcon(.secondary))
        .disabled(true)
        Button { } label: {
            LabcordIconArtwork(icon: .plus, size: 20)
        }
        .buttonStyle(.labcordIcon(.primary, isLoading: true))
        Button { } label: {
            LabcordIconArtwork(icon: .plus, size: 34)
        }
        .buttonStyle(.labcordIcon(.primary, size: .extraLarge))
    }
    .padding()
}

public typealias IconButtonStyle = IOSIconButtonStyle
