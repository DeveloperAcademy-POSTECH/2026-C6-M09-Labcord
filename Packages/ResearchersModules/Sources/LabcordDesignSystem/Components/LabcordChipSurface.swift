import SwiftUI

struct LabcordChipSurface<Content: View>: View {
    let size: LabcordControlSize?
    let visualStyle: LabcordChipVisualStyle
    let emphasis: LabcordChipEmphasis
    let isSelected: Bool
    let isDisabled: Bool
    let content: Content

    @Environment(\.controlSize) private var controlSize
    @Environment(\.labcordTheme) private var theme

    init(
        size: LabcordControlSize?,
        visualStyle: LabcordChipVisualStyle,
        emphasis: LabcordChipEmphasis,
        isSelected: Bool,
        isDisabled: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.size = size
        self.visualStyle = visualStyle
        self.emphasis = emphasis
        self.isSelected = isSelected
        self.isDisabled = isDisabled
        self.content = content()
    }

    var body: some View {
        HStack(spacing: LabcordChipMetrics.iconGap(for: resolvedSize)) {
            content
        }
            .typography(typography)
            .foregroundStyle(LabcordColor(foregroundToken))
            .labcordMotion(.state, value: foregroundToken)
            .padding(.horizontal, horizontalPadding + (borderToken == nil ? 0 : 1))
            .frame(minHeight: height)
            .background {
                Rectangle()
                    .fill(LabcordColor(fillToken ?? .fillPrimary))
                    .opacity(fillToken == nil ? 0 : 1)
                    .labcordMotion(.state, value: fillToken)
                    .allowsHitTesting(false)
            }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(LabcordColor(borderToken ?? .borderDefault), lineWidth: 1)
                    .opacity(borderToken == nil ? 0 : 1)
                    .labcordMotion(.state, value: borderToken)
                    .allowsHitTesting(false)
            }
            .contentShape(Capsule())
            .disabled(isDisabled)
    }

    private var resolvedSize: LabcordControlSize {
        switch size ?? LabcordControlSize(controlSize) {
        case .small, .medium:
            return .small
        case .large:
            return .large
        }
    }

    private var height: CGFloat {
        resolvedSize == .large ? 50 : 32
    }

    private var horizontalPadding: CGFloat {
        resolvedSize == .large ? theme.layout.spacing16 : theme.layout.spacing12
    }

    private var typography: TypographyStyle {
        resolvedSize == .large ? Typography.body : Typography.subheadline
    }

    private var foregroundToken: ColorToken {
        if isDisabled {
            return .labelDisabled
        }

        if isSelected {
            return emphasis == .strong ? .fillWhite : .brandOnSubtle
        }

        return .labelPrimary
    }

    private var fillToken: ColorToken? {
        if isDisabled {
            return .fillDisabled
        }

        if isSelected {
            if emphasis == .strong {
                return .brandPrimary
            }
            return visualStyle == .solid ? .brandSubtle : nil
        }

        return visualStyle == .solid ? .fillPrimary : nil
    }

    private var borderToken: ColorToken? {
        guard visualStyle == .outline else { return nil }
        if isDisabled || !isSelected {
            return .borderDefault
        }
        return emphasis == .weak ? .brandBorder : nil
    }
}

enum LabcordChipMetrics {
    static func iconGap(for size: LabcordControlSize) -> CGFloat {
        size == .large ? 8 : 4
    }
    static let leadingIconSize: CGFloat = 16
    static let dismissIconSize: CGFloat = 14
}
