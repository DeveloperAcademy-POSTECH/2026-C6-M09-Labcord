import SwiftUI
#if os(iOS)
import UIKit

struct TimePickerWheel: UIViewRepresentable {
    let title: String
    let selection: Binding<Int>
    let count: Int
    let scale: CGFloat

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
                min(max(selection.wrappedValue, 0), count - 1), inComponent: 0, animated: false
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
        private var parent: TimePickerWheel
        private var color: UIColor?
        var lastSelectedValue: Int?

        init(_ parent: TimePickerWheel) {
            self.parent = parent
        }

        func update(_ parent: TimePickerWheel) -> Bool {
            let nextColor = UIColor(Color("Experiment/Label/Primary", bundle: .module))
            let changed = parent.scale != self.parent.scale || color != nextColor
            self.parent = parent
            color = nextColor
            return changed
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

        func pickerView(
            _ pickerView: UIPickerView, numberOfRowsInComponent component: Int
        ) -> Int {
            parent.count
        }

        func pickerView(
            _ pickerView: UIPickerView, rowHeightForComponent component: Int
        ) -> CGFloat {
            34.8 * parent.scale
        }

        func pickerView(
            _ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int
        ) -> String? {
            String(format: "%02d", row)
        }

        func pickerView(
            _ pickerView: UIPickerView, viewForRow row: Int,
            forComponent component: Int, reusing view: UIView?
        ) -> UIView {
            let label = view as? UILabel ?? UILabel()
            label.textAlignment = .center
            label.isAccessibilityElement = false
            let size = 22 * parent.scale
            let font = UIFont(name: "PretendardVariable-Regular", size: size)
                ?? .systemFont(ofSize: size, weight: .regular)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let tracking: CGFloat = -0.26
            label.attributedText = NSAttributedString(
                string: String(format: "%02d", row),
                attributes: [
                    .font: font,
                    .foregroundColor: color ?? UIColor.label,
                    .kern: tracking * parent.scale,
                    .paragraphStyle: paragraph
                ]
            )
            return label
        }

        func pickerView(
            _ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int
        ) {
            lastSelectedValue = row
            parent.selection.transaction(parent.selection.transaction).wrappedValue = row
        }

        func pickerView(
            _ pickerView: UIPickerView, accessibilityLabelForComponent component: Int
        ) -> String? {
            parent.title
        }
    }
}

#endif
