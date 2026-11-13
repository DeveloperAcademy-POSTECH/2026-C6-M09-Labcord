import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct ExperimentReviewActions: View {
    let retakeLabel: String
    let isSaving: Bool
    let showsAutoSaveNotice: Bool
    let onRetake: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if showsAutoSaveNotice {
                StatusPill("3초 후 자동 저장돼요", showIcon: false)
            }

            HStack(spacing: 12) {
                ExperimentReviewIconButton(
                    icon: .arrowCounterClockwise,
                    label: retakeLabel,
                    isEnabled: !isSaving,
                    action: onRetake
                )

                Button(action: onSave) {
                    Label {
                        Text("지금 저장")
                    } icon: {
                        Image(labcordIcon: .check)
                    }
                }
                .buttonStyle(.labcord(.filled, size: .large, colorPalette: .experiment))
                .disabled(isSaving)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct ExperimentReviewIconButton: View {
    let icon: Icon
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        ExperimentControlButton(
            state: isEnabled ? .default : .disabled,
            action: action
        ) {
            Image(labcordIcon: icon)
        }
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .background(
            VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        )
        .cornerRadius(LayoutTokens.radiusFull)
    }
}
