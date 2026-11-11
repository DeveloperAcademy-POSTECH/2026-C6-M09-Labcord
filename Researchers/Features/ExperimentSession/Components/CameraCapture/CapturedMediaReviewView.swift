import LabcordDesignSystem
import SwiftUI

struct CapturedMediaReviewView<Content: View>: View {
    let title: String
    let onRetake: () -> Void
    let onClose: () -> Void
    let onSave: (() -> Void)?
    let isSaving: Bool
    let isCloseEnabled: Bool
    let showsAutoSaveNotice: Bool
    @ViewBuilder let content: (CGSize) -> Content

    init(
        title: String,
        onRetake: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onSave: (() -> Void)? = nil,
        isSaving: Bool = false,
        isCloseEnabled: Bool = true,
        showsAutoSaveNotice: Bool = true,
        @ViewBuilder content: @escaping (CGSize) -> Content
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
            ZStack {
                Color("General/Overlay/Scrim")

                ZStack {
                    content(geometry.size)
                        .overlay {
                            VStack {
                                HStack(spacing: 12) {
                                    ExperimentControlButton(
                                        state: isCloseEnabled ? .default : .disabled,
                                        action: onClose
                                    ) {
                                        Image(labcordIcon: .x)
                                    }
                                    .background(
                                        VisualEffectView(
                                                    effect: UIBlurEffect(
                                                        style: .systemUltraThinMaterial
                                                    )
                                        )
                                    )
                                    .cornerRadius(LayoutTokens.radiusFull)

                                    Text(title)
                                        .typography(Typography.headline)
                                        .foregroundStyle(Color("Experiment/Label/Primary"))

                                    Spacer()
                                }

                                Spacer()

                                HStack {
                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 12) {
                                        if showsAutoSaveNotice {
                                            StatusPill("3초 후 자동 저장돼요", showIcon: false)
                                        }

                                        HStack(spacing: 12) {
                                            ExperimentControlButton(
                                                state: isCloseEnabled ? .default : .disabled,
                                                action: onRetake
                                            ) {
                                                Image(labcordIcon: .arrowCounterClockwise)
                                            }
                                            .background(
                                                VisualEffectView(
                                                    effect: UIBlurEffect(
                                                        style: .systemUltraThinMaterial
                                                    )
                                                )
                                            )
                                            .cornerRadius(LayoutTokens.radiusFull)

                                            if let onSave {
                                                Button(action: onSave) {
                                                    Label {
                                                        Text("지금 저장")
                                                    } icon: {
                                                        Image(labcordIcon: .check)
                                                    }
                                                    .labelStyle(.titleAndIcon)
                                                }
                                                .buttonStyle(
                                                    .labcord(
                                                        .filled,
                                                        size: .large,
                                                        colorPalette: .experiment
                                                    )
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(16)
                        }
                }
                .padding(.horizontal, 16)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }
}
