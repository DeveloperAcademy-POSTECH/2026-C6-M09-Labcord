import SwiftUI

struct LabcordChipSurface<Content: View>: View {
    let size: ComponentSize?
    let visualStyle: ChipVisualStyle
    let emphasis: ChipEmphasis
    let isSelected: Bool
    let isDisabled: Bool
    let content: Content

    @Environment(\.controlSize) private var controlSize
    private let layout = LayoutTokens()

    init(
        size: ComponentSize?,
        visualStyle: ChipVisualStyle,
        emphasis: ChipEmphasis,
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
            .foregroundStyle((foregroundColor))
            .labcordMotion(.state, value: foregroundColor)
            .padding(.horizontal, horizontalPadding + (borderColor == nil ? 0 : 1))
            .frame(minHeight: height)
            .background {
                Rectangle()
                    .fill((fillColor ?? Color("General/Fill/Primary", bundle: .module)))
                    .opacity(fillColor == nil ? 0 : 1)
                    .labcordMotion(.state, value: fillColor)
                    .allowsHitTesting(false)
            }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        borderColor ?? Color("General/Border/Default", bundle: .module),
                        lineWidth: 1
                    )
                    .opacity(borderColor == nil ? 0 : 1)
                    .labcordMotion(.state, value: borderColor)
                    .allowsHitTesting(false)
            }
            .contentShape(Capsule())
            .disabled(isDisabled)
    }

    private var resolvedSize: ComponentSize {
        switch size ?? ComponentSize(controlSize) {
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
        resolvedSize == .large ? layout.spacing16 : layout.spacing12
    }

    private var typography: TypographyStyle {
        resolvedSize == .large ? Typography.body : Typography.subheadline
    }

    private var foregroundColor: Color {
        if isDisabled {
            return Color("General/Label/Disabled", bundle: .module)
        }

        if isSelected {
            return emphasis == .strong
                ? Color("General/Fill/White", bundle: .module)
                : Color("General/Brand/On Subtle", bundle: .module)
        }

        return Color("General/Label/Primary", bundle: .module)
    }

    private var fillColor: Color? {
        if isDisabled {
            return Color("General/Fill/Disabled", bundle: .module)
        }

        if isSelected {
            if emphasis == .strong {
                return Color("General/Brand/Primary", bundle: .module)
            }
            return visualStyle == .solid ? Color("General/Brand/Subtle", bundle: .module) : nil
        }

        return visualStyle == .solid ? Color("General/Fill/Primary", bundle: .module) : nil
    }

    private var borderColor: Color? {
        guard visualStyle == .outline else { return nil }
        if isDisabled || !isSelected {
            return Color("General/Border/Default", bundle: .module)
        }
        return emphasis == .weak ? Color("General/Brand/Border", bundle: .module) : nil
    }
}

enum LabcordChipMetrics {
    static func iconGap(for size: ComponentSize) -> CGFloat {
        size == .large ? 8 : 4
    }
    static let leadingIconSize: CGFloat = 16
    static let dismissIconSize: CGFloat = 14
}
