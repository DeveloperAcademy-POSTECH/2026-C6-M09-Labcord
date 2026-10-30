import SwiftUI

struct CapturedMediaReviewView<Content: View>: View {
    let onRetake: () -> Void
    @ViewBuilder let content: (CGSize) -> Content

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.75)

                VStack(spacing: 16) {
                    content(geometry.size)

                    Button("다시찍기", action: onRetake)
                        .buttonStyle(.borderedProminent)
                }
                .padding(20)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }
}
