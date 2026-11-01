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
        ChipToggleBody(
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
        ChipButtonBody(
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
        ChipSurface(
            size: size,
            visualStyle: visualStyle,
            emphasis: emphasis,
            isSelected: isSelected,
            isDisabled: !isEnabled
        ) {
            Toggle(isOn: $isSelected) {
                HStack(spacing: ChipMetrics.iconGap(for: resolvedSize)) {
                    if let leadingIcon {
                        IconArtwork(
                            icon: leadingIcon,
                            size: usesLargeMetrics ? 24 : ChipMetrics.leadingIconSize,
                            relativeTo: resolvedTextStyle
                        )
                    }

                    Text(label)
                }
            }
            .toggleStyle(ChipInlineToggleStyle())

            if let onDismiss {
                Button(action: onDismiss) {
                    IconArtwork(
                        icon: .x,
                        size: usesLargeMetrics ? 24 : ChipMetrics.dismissIconSize,
                        relativeTo: resolvedTextStyle
                    )
                }
                .buttonStyle(PressFeedbackButtonStyle())
                .accessibilityLabel(Text("\(label) 제거"))
            }
        }
    }

    private var resolvedTextStyle: Font.TextStyle {
        switch resolvedSize {
        case .large, .extraLarge:
            return .body
        case .small, .medium:
            return .subheadline
        }
    }

    private var resolvedSize: ComponentSize {
        size ?? ComponentSize(controlSize)
    }

    private var usesLargeMetrics: Bool {
        resolvedSize == .large || resolvedSize == .extraLarge
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

private struct ChipToggleBody: View {
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
        ChipSurface(
            size: size,
            visualStyle: visualStyle,
            emphasis: emphasis,
            isSelected: configuration.isOn,
            isDisabled: isDisabled || !isEnabled
        ) {
            ChipInlineToggleStyle().makeBody(configuration: configuration)
        }
    }
}

private struct ChipButtonBody: View {
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
        ChipSurface(
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

private struct ChipInlineToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
        }
        .buttonStyle(PressFeedbackButtonStyle())
        .accessibilityValue(configuration.isOn ? "선택됨" : "선택 안 됨")
    }
}

#Preview("칩 · 선택과 버튼") {
    @Previewable @State var isSelected = true
    _ = FontRegistration.register()
    return VStack(alignment: .leading, spacing: 12) {
        Chip(isSelected: $isSelected, label: "실험 기록")
        Toggle("선택 칩", isOn: $isSelected).toggleStyle(.labcordChip(style: .outline))
        Toggle("약한 솔리드", isOn: $isSelected)
            .toggleStyle(.labcordChip(style: .solid, emphasis: .weak))
        Toggle("약한 외곽선", isOn: $isSelected)
            .toggleStyle(.labcordChip(style: .outline, emphasis: .weak))
        Button("버튼 칩") {}.buttonStyle(.labcordChip())
    }
}
