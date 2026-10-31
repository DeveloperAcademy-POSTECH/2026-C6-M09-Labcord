import SwiftUI

@MainActor
public struct LabcordCheckboxStyle: ToggleStyle {
    private let size: LabcordControlSize?

    public init(size: LabcordControlSize? = nil) {
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        LabcordCheckboxToggleBody(configuration: configuration, size: size)
    }
}

public extension ToggleStyle where Self == LabcordCheckboxStyle {
    static func labcordCheckbox(size: LabcordControlSize? = nil) -> LabcordCheckboxStyle {
        LabcordCheckboxStyle(size: size)
    }
}

@MainActor
private struct LabcordCheckboxToggleBody: View {
    let configuration: ToggleStyleConfiguration
    let size: LabcordControlSize?
    @Environment(\.labelsVisibility) private var labelsVisibility

    var body: some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                LabcordSelectionIndicator(
                    kind: .checkbox, isSelected: configuration.isOn, size: size
                )
                if labelsVisibility != .hidden {
                    configuration.label
                        .typography(Typography.body)
                        .foregroundStyle(.labcord(.labelPrimary))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LabcordPlainButtonStyle())
        .accessibilityRepresentation {
            Toggle(configuration).toggleStyle(.switch)
        }
    }
}

struct LabcordSelectionIndicator: View {
    enum Kind { case checkbox, radio }

    let kind: Kind
    let isSelected: Bool
    var size: LabcordControlSize?
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    private var resolvedSize: LabcordControlSize { size ?? LabcordControlSize(controlSize) }
    private var dimension: CGFloat {
        switch resolvedSize {
        case .small: 16
        case .medium: 24
        case .large: 32
        }
    }
    private var checkSize: CGFloat {
        switch resolvedSize {
        case .small: 12
        case .medium: 14
        case .large: 18
        }
    }
    private var dotSize: CGFloat {
        switch resolvedSize {
        case .small: 6
        case .medium: 10
        case .large: 12
        }
    }
    private var radioStroke: CGFloat { isSelected ? 1 : (resolvedSize == .small ? 1.5 : 2) }

    var body: some View {
        Group {
            switch kind {
            case .checkbox: checkbox
            case .radio: radio
            }
        }
        .frame(width: dimension * scale, height: dimension * scale)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isSelected)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var checkbox: some View {
        let shape = RoundedRectangle(
            cornerRadius: (resolvedSize == .large ? 8 : 4) * scale, style: .circular
        )
        return shape
            .fill(.labcord(.fillPrimaryBrand))
            .opacity(isSelected ? 1 : 0)
            .overlay {
                shape.strokeBorder(
                    .labcord(isSelected ? .fillPrimaryBrand : .borderDefault),
                    lineWidth: 1.5 * scale
                )
            }
            .overlay {
                if isSelected {
                    LabcordIconArtwork(icon: .checkBold, size: checkSize)
                        .foregroundStyle(.labcord(.labelInverse))
                        .transition(.opacity)
                }
            }
    }

    private var radio: some View {
        Circle()
            .inset(by: isSelected ? -scale : 0)
            .fill(.labcord(.fillPrimaryBrand))
            .opacity(isSelected ? 1 : 0)
            .overlay {
                if !isSelected {
                    Circle()
                        .strokeBorder(.labcord(.borderDefault), lineWidth: radioStroke * scale)
                }
            }
            .overlay {
                if isSelected {
                    Circle()
                        .fill(.labcord(.fillLight))
                        .frame(width: dotSize * scale, height: dotSize * scale)
                        .transition(.opacity)
                }
            }
    }
}
