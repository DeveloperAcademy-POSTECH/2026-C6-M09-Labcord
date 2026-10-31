import SwiftUI

public enum LabcordChipVisualStyle: String, Sendable {
    case solid
    case outline
}

public enum LabcordChipEmphasis: String, Sendable {
    case strong
    case weak
}

public struct LabcordChipStyle: ToggleStyle {
    private let size: LabcordControlSize?
    private let visualStyle: LabcordChipVisualStyle
    private let emphasis: LabcordChipEmphasis
    private let isDisabled: Bool

    public init(
        size: LabcordControlSize? = nil,
        style: LabcordChipVisualStyle = .solid,
        emphasis: LabcordChipEmphasis = .strong,
        isDisabled: Bool = false
    ) {
        self.size = size
        visualStyle = style
        self.emphasis = emphasis
        self.isDisabled = isDisabled
    }

    public func makeBody(configuration: Configuration) -> some View {
        LabcordChipToggleBody(
            configuration: configuration,
            size: size,
            visualStyle: visualStyle,
            emphasis: emphasis,
            isDisabled: isDisabled
        )
    }
}

public struct LabcordChipButtonStyle: ButtonStyle {
    private let size: LabcordControlSize?
    private let visualStyle: LabcordChipVisualStyle
    private let emphasis: LabcordChipEmphasis
    private let isSelected: Bool

    public init(
        size: LabcordControlSize? = nil,
        style: LabcordChipVisualStyle = .solid,
        emphasis: LabcordChipEmphasis = .strong,
        isSelected: Bool = false
    ) {
        self.size = size
        visualStyle = style
        self.emphasis = emphasis
        self.isSelected = isSelected
    }

    public func makeBody(configuration: Configuration) -> some View {
        LabcordChipButtonBody(
            configuration: configuration,
            size: size,
            visualStyle: visualStyle,
            emphasis: emphasis,
            isSelected: isSelected
        )
    }
}

public struct LabcordChip: View {
    @Binding private var isSelected: Bool

    private let label: String
    private let leadingIcon: LabcordIcon?
    private let size: LabcordControlSize?
    private let visualStyle: LabcordChipVisualStyle
    private let emphasis: LabcordChipEmphasis
    private let onDismiss: (() -> Void)?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    public init(
        isSelected: Binding<Bool>,
        label: String,
        leadingIcon: LabcordIcon? = nil,
        size: LabcordControlSize? = nil,
        style: LabcordChipVisualStyle = .solid,
        emphasis: LabcordChipEmphasis = .strong,
        onDismiss: (() -> Void)? = nil
    ) {
        _isSelected = isSelected
        self.label = label
        self.leadingIcon = leadingIcon
        self.size = size
        visualStyle = style
        self.emphasis = emphasis
        self.onDismiss = onDismiss
    }

    public var body: some View {
        LabcordChipSurface(
            size: size,
            visualStyle: visualStyle,
            emphasis: emphasis,
            isSelected: isSelected,
            isDisabled: !isEnabled
        ) {
            Toggle(isOn: $isSelected) {
                HStack(spacing: LabcordChipMetrics.iconGap(for: resolvedSize)) {
                    if let leadingIcon {
                        LabcordIconArtwork(
                            icon: leadingIcon,
                            size: resolvedSize == .large ? 24 : LabcordChipMetrics.leadingIconSize,
                            relativeTo: resolvedTextStyle
                        )
                    }

                    Text(label)
                }
            }
            .toggleStyle(LabcordChipInlineToggleStyle())

            if let onDismiss {
                Button(action: onDismiss) {
                    LabcordIconArtwork(
                        icon: .x,
                        size: resolvedSize == .large ? 24 : LabcordChipMetrics.dismissIconSize,
                        relativeTo: resolvedTextStyle
                    )
                }
                .buttonStyle(LabcordPlainButtonStyle())
                .accessibilityLabel(Text("\(label) 제거"))
            }
        }
    }

    private var resolvedTextStyle: Font.TextStyle {
        switch resolvedSize {
        case .large:
            return .body
        case .small, .medium:
            return .subheadline
        }
    }

    private var resolvedSize: LabcordControlSize {
        size ?? LabcordControlSize(controlSize)
    }
}

public extension ToggleStyle where Self == LabcordChipStyle {
    static func labcordChip(
        size: LabcordControlSize? = nil,
        style: LabcordChipVisualStyle = .solid,
        emphasis: LabcordChipEmphasis = .strong,
        isDisabled: Bool = false
    ) -> LabcordChipStyle {
        LabcordChipStyle(
            size: size,
            style: style,
            emphasis: emphasis,
            isDisabled: isDisabled
        )
    }
}

public extension ButtonStyle where Self == LabcordChipButtonStyle {
    static func labcordChip(
        size: LabcordControlSize? = nil,
        style: LabcordChipVisualStyle = .solid,
        emphasis: LabcordChipEmphasis = .strong,
        isSelected: Bool = false
    ) -> LabcordChipButtonStyle {
        LabcordChipButtonStyle(
            size: size,
            style: style,
            emphasis: emphasis,
            isSelected: isSelected
        )
    }
}

private struct LabcordChipToggleBody: View {
    nonisolated(unsafe) let configuration: ToggleStyleConfiguration
    let size: LabcordControlSize?
    let visualStyle: LabcordChipVisualStyle
    let emphasis: LabcordChipEmphasis
    let isDisabled: Bool

    @Environment(\.isEnabled) private var isEnabled

    nonisolated init(
        configuration: ToggleStyleConfiguration,
        size: LabcordControlSize?,
        visualStyle: LabcordChipVisualStyle,
        emphasis: LabcordChipEmphasis,
        isDisabled: Bool
    ) {
        self.configuration = configuration
        self.size = size
        self.visualStyle = visualStyle
        self.emphasis = emphasis
        self.isDisabled = isDisabled
    }

    var body: some View {
        LabcordChipSurface(
            size: size,
            visualStyle: visualStyle,
            emphasis: emphasis,
            isSelected: configuration.isOn,
            isDisabled: isDisabled || !isEnabled
        ) {
            LabcordChipInlineToggleStyle().makeBody(configuration: configuration)
        }
    }
}

private struct LabcordChipButtonBody: View {
    nonisolated(unsafe) let configuration: ButtonStyleConfiguration
    let size: LabcordControlSize?
    let visualStyle: LabcordChipVisualStyle
    let emphasis: LabcordChipEmphasis
    let isSelected: Bool

    @Environment(\.isEnabled) private var isEnabled

    nonisolated init(
        configuration: ButtonStyleConfiguration,
        size: LabcordControlSize?,
        visualStyle: LabcordChipVisualStyle,
        emphasis: LabcordChipEmphasis,
        isSelected: Bool
    ) {
        self.configuration = configuration
        self.size = size
        self.visualStyle = visualStyle
        self.emphasis = emphasis
        self.isSelected = isSelected
    }

    var body: some View {
        LabcordChipSurface(
            size: size,
            visualStyle: visualStyle,
            emphasis: emphasis,
            isSelected: isSelected,
            isDisabled: !isEnabled
        ) {
            configuration.label
        }
        .labcordPressFeedback(configuration.isPressed, isSubtle: true)
    }
}

private struct LabcordChipInlineToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
        }
        .buttonStyle(LabcordPlainButtonStyle())
        .accessibilityValue(configuration.isOn ? "선택됨" : "선택 안 됨")
    }
}
