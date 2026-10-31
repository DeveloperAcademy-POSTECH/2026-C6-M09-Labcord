import SwiftUI

public struct LabcordRadioButton<Value: Hashable, Label: View>: View {
    private let value: Value
    @Binding private var selection: Value
    private let size: LabcordControlSize?
    private let label: Label
    @Environment(\.labelsVisibility) private var labelsVisibility

    public init(
        value: Value,
        selection: Binding<Value>,
        size: LabcordControlSize? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self.value = value
        _selection = selection
        self.size = size
        self.label = label()
    }

    private var isSelected: Bool { selection == value }

    public var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                LabcordSelectionIndicator(kind: .radio, isSelected: isSelected, size: size)
                if labelsVisibility != .hidden {
                    label
                        .typography(Typography.body)
                        .foregroundStyle(.labcord(.labelPrimary))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LabcordPlainButtonStyle())
        .accessibilityRepresentation {
            Button(action: select) { label }
                .accessibilityValue(Text(isSelected ? "선택됨" : "선택 안 됨"))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private func select() {
        if !isSelected { selection = value }
    }
}

public extension LabcordRadioButton where Label == Text {
    init(
        _ title: LocalizedStringKey,
        value: Value,
        selection: Binding<Value>,
        size: LabcordControlSize? = nil
    ) {
        self.init(value: value, selection: selection, size: size) { Text(title) }
    }
}
