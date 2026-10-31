import SwiftUI

public enum ChipVisualStyle: String, Sendable {
    case solid
    case outline
}

public enum ChipEmphasis: String, Sendable {
    case strong
    case weak
}

public struct ChipStyle: ToggleStyle {
    private let size: ComponentSize?
    private let visualStyle: ChipVisualStyle
    private let emphasis: ChipEmphasis
    private let isDisabled: Bool

    public init(
        size: ComponentSize? = nil,
        style: ChipVisualStyle = .solid,
        emphasis: ChipEmphasis = .strong,
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

public struct ChipButtonStyle: ButtonStyle {
    private let size: ComponentSize?
    private let visualStyle: ChipVisualStyle
    private let emphasis: ChipEmphasis
    private let isSelected: Bool

    public init(
        size: ComponentSize? = nil,
        style: ChipVisualStyle = .solid,
        emphasis: ChipEmphasis = .strong,
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

public struct Chip: View {
    @Binding private var isSelected: Bool

    private let label: String
    private let leadingIcon: Icon?
    private let size: ComponentSize?
    private let visualStyle: ChipVisualStyle
    private let emphasis: ChipEmphasis
    private let onDismiss: (() -> Void)?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    public init(
        isSelected: Binding<Bool>,
        label: String,
        leadingIcon: Icon? = nil,
        size: ComponentSize? = nil,
        style: ChipVisualStyle = .solid,
        emphasis: ChipEmphasis = .strong,
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

    private var resolvedSize: ComponentSize {
        size ?? ComponentSize(controlSize)
    }
}

public extension ToggleStyle where Self == ChipStyle {
    static func labcordChip(
        size: ComponentSize? = nil,
        style: ChipVisualStyle = .solid,
        emphasis: ChipEmphasis = .strong,
        isDisabled: Bool = false
    ) -> ChipStyle {
        ChipStyle(
            size: size,
            style: style,
            emphasis: emphasis,
            isDisabled: isDisabled
        )
    }
}

public extension ButtonStyle where Self == ChipButtonStyle {
    static func labcordChip(
        size: ComponentSize? = nil,
        style: ChipVisualStyle = .solid,
        emphasis: ChipEmphasis = .strong,
        isSelected: Bool = false
    ) -> ChipButtonStyle {
        ChipButtonStyle(
            size: size,
            style: style,
            emphasis: emphasis,
            isSelected: isSelected
        )
    }
}

private struct LabcordChipToggleBody: View {
    nonisolated(unsafe) let configuration: ToggleStyleConfiguration
    let size: ComponentSize?
    let visualStyle: ChipVisualStyle
    let emphasis: ChipEmphasis
    let isDisabled: Bool

    @Environment(\.isEnabled) private var isEnabled

    nonisolated init(
        configuration: ToggleStyleConfiguration,
        size: ComponentSize?,
        visualStyle: ChipVisualStyle,
        emphasis: ChipEmphasis,
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
    let size: ComponentSize?
    let visualStyle: ChipVisualStyle
    let emphasis: ChipEmphasis
    let isSelected: Bool

    @Environment(\.isEnabled) private var isEnabled

    nonisolated init(
        configuration: ButtonStyleConfiguration,
        size: ComponentSize?,
        visualStyle: ChipVisualStyle,
        emphasis: ChipEmphasis,
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

#Preview("칩 · 선택과 버튼") {
    @Previewable @State var isSelected = true
    _ = FontRegistration.register()
    return VStack(alignment: .leading, spacing: 12) {
        Chip(isSelected: $isSelected, label: "실험 기록")
        Toggle("선택 칩", isOn: $isSelected).toggleStyle(.labcordChip(style: .outline))
        Button("버튼 칩") {}.buttonStyle(.labcordChip())
    }
}
