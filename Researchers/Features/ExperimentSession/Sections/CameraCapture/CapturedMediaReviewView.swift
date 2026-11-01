import SwiftUI

struct CapturedMediaReviewView<Content: View>: View {
    let onRetake: () -> Void
    let onSave: (() -> Void)?
    let isSaving: Bool
    @ViewBuilder let content: (CGSize) -> Content

    init(
        onRetake: @escaping () -> Void,
        onSave: (() -> Void)? = nil,
        isSaving: Bool = false,
        @ViewBuilder content: @escaping (CGSize) -> Content
    ) {
        self.onRetake = onRetake
        self.onSave = onSave
        self.isSaving = isSaving
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.75)

                VStack(spacing: 16) {
                    content(geometry.size)

                    HStack(spacing: 12) {
                        Button("다시찍기", action: onRetake)
                            .disabled(isSaving)

                        if let onSave {
                            Button(isSaving ? "저장 중..." : "지금 저장", action: onSave)
                                .disabled(isSaving)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }
}
