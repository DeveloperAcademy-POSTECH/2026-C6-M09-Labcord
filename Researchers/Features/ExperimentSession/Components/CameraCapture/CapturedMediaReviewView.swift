import LabcordDesignSystem
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
        CapturedMediaOverlay {
            content()
        } controls: {
            reviewControls
        }
    }

    private var reviewControls: some View {
        VStack {
            HStack(spacing: 12) {
                ExperimentReviewIconButton(
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

            ExperimentReviewActions(
                retakeLabel: "다시 찍기",
                isSaving: isSaving,
                showsAutoSaveNotice: showsAutoSaveNotice,
                onRetake: onRetake,
                onSave: onSave
            )
        }
        .padding(16)
    }
}

struct CapturedMediaOverlay<Content: View, Controls: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let controls: () -> Controls

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
                    .overlay { controls() }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }
}
