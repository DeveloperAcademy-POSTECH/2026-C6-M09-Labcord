import SwiftUI
#if os(iOS)
import UIKit

struct TimePickerWheel: UIViewRepresentable {
    let title: String
    let selection: Binding<Int>
    let count: Int
    let scale: CGFloat
    let color: Color
    let adjacentColor: Color
    let distantColor: Color

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIPickerView {
        FontRegistration.register()
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        let coordinator = context.coordinator
        let appearanceChanged = coordinator.update(self)
        picker.isUserInteractionEnabled = context.environment.isEnabled
        picker.alpha = context.environment.isEnabled ? 1 : 0.4
        if context.environment.isEnabled {
            picker.accessibilityTraits.remove(.notEnabled)
        } else {
            picker.accessibilityTraits.insert(.notEnabled)
        }

        if coordinator.lastSelectedValue != selection.wrappedValue {
            picker.selectRow(
                coordinator.centerRow(for: min(max(selection.wrappedValue, 0), count - 1)),
                inComponent: 0, animated: false
            )
            coordinator.lastSelectedValue = selection.wrappedValue
            picker.reloadAllComponents()
        } else if appearanceChanged {
            picker.reloadAllComponents()
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: UIPickerView, context: Context
    ) -> CGSize? {
        CGSize(width: proposal.width ?? 76, height: 174 * scale)
    }

    @MainActor
    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewAccessibilityDelegate {
        private let cycleCount = 9
        private var parent: TimePickerWheel
        private var color: UIColor?
        private var adjacentColor: UIColor?
        private var distantColor: UIColor?
        var lastSelectedValue: Int?

        init(_ parent: TimePickerWheel) {
            self.parent = parent
        }

        func update(_ parent: TimePickerWheel) -> Bool {
            let nextColor = UIColor(parent.color)
            let nextAdjacentColor = UIColor(parent.adjacentColor)
            let nextDistantColor = UIColor(parent.distantColor)
            let changed = parent.scale != self.parent.scale || color != nextColor
                || adjacentColor != nextAdjacentColor || distantColor != nextDistantColor
            self.parent = parent
            color = nextColor
            adjacentColor = nextAdjacentColor
            distantColor = nextDistantColor
            return changed
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

        func centerRow(for value: Int) -> Int {
            (cycleCount / 2) * parent.count + value
        }

        func pickerView(
            _ pickerView: UIPickerView, numberOfRowsInComponent component: Int
        ) -> Int {
            parent.count * cycleCount
        }

        func pickerView(
            _ pickerView: UIPickerView, rowHeightForComponent component: Int
        ) -> CGFloat {
            34.8 * parent.scale
        }

        func pickerView(
            _ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int
        ) -> String? {
            String(format: "%02d", row % parent.count)
        }

        func pickerView(
            _ pickerView: UIPickerView, viewForRow row: Int,
            forComponent component: Int, reusing view: UIView?
        ) -> UIView {
            let label = view as? UILabel ?? UILabel()
            label.textAlignment = .center
            label.isAccessibilityElement = false
            let distance = abs(row - pickerView.selectedRow(inComponent: component))
            let size: CGFloat = distance == 0 ? 22 : (distance == 1 ? 17 : 12)
            let weight: UIFont.Weight = distance == 0 ? .regular : .semibold
            let baseFont = UIFont(name: "PretendardVariable-Regular", size: size * parent.scale)
                ?? .systemFont(ofSize: size * parent.scale)
            let descriptor = baseFont.fontDescriptor.addingAttributes([
                .traits: [UIFontDescriptor.TraitKey.weight: weight]
            ])
            let font = UIFont(descriptor: descriptor, size: size * parent.scale)
            let rowColor = distance == 0 ? color : (distance == 1 ? adjacentColor : distantColor)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let tracking: CGFloat = distance == 0 ? -0.26 : (distance == 1 ? -0.43 : 0)
            label.attributedText = NSAttributedString(
                string: String(format: "%02d", row % parent.count),
                attributes: [
                    .font: font,
                    .foregroundColor: rowColor ?? UIColor.label,
                    .kern: tracking * parent.scale,
                    .paragraphStyle: paragraph
                ]
            )
            return label
        }

        func pickerView(
            _ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int
        ) {
            let value = row % parent.count
            lastSelectedValue = value
            parent.selection.transaction(parent.selection.transaction).wrappedValue = value
            if row < parent.count * 2 || row >= parent.count * (cycleCount - 2) {
                pickerView.selectRow(
                    centerRow(for: value), inComponent: component, animated: false
                )
            }
            pickerView.reloadAllComponents()
        }

        func pickerView(
            _ pickerView: UIPickerView, accessibilityLabelForComponent component: Int
        ) -> String? {
            parent.title
        }
    }
}

#endif
