import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct CapturedMediaReviewView<Content: View>: View {
    let title: String
    let onRetake: () -> Void
    let onClose: () -> Void
    let onSave: () -> Void
    let isSaving: Bool
    let isCloseEnabled: Bool
    let showsAutoSaveNotice: Bool
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        onRetake: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onSave: @escaping () -> Void,
        isSaving: Bool,
        isCloseEnabled: Bool = true,
        showsAutoSaveNotice: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.onRetake = onRetake
        self.onClose = onClose
        self.onSave = onSave
        self.isSaving = isSaving
        self.isCloseEnabled = isCloseEnabled
        self.showsAutoSaveNotice = showsAutoSaveNotice
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let mediaSize = isLandscape
                ? CGSize(
                    width: geometry.size.width * 710 / 874,
                    height: geometry.size.height * 362 / 402
                )
                : CGSize(
                    width: geometry.size.width * 370 / 402,
                    height: geometry.size.height * 683 / 874
                )

            ZStack {
                Color("General/Overlay/Scrim")

                content()
                    .frame(width: mediaSize.width, height: mediaSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay { reviewControls }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }

    private var reviewControls: some View {
        VStack {
            HStack(spacing: 12) {
                controlButton(
                    icon: .x,
                    label: "저장하지 않고 닫기",
                    isEnabled: isCloseEnabled,
                    action: onClose
                )

                Text(title)
                    .typography(Typography.headline)
                    .foregroundStyle(Color("Experiment/Label/Primary"))

                Spacer()
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 12) {
                if showsAutoSaveNotice {
                    StatusPill("3초 후 자동 저장돼요", showIcon: false)
                }

                HStack(spacing: 12) {
                    controlButton(
                        icon: .arrowCounterClockwise,
                        label: "다시 찍기",
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
        .padding(16)
    }

    private func controlButton(
        icon: Icon,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        ExperimentControlButton(
            state: isEnabled ? .default : .disabled,
            action: action
        ) {
            Image(labcordIcon: icon)
        }
        .accessibilityLabel(label)
        .background(
            VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        )
        .cornerRadius(LayoutTokens.radiusFull)
    }
}
