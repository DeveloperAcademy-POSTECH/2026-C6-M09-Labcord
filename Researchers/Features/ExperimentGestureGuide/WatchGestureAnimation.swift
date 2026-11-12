import Lottie
import SwiftUI

struct WatchGestureAnimation: View {
    let name: String
    @State private var animation: LottieAnimation?

    var body: some View {
        LottieView(animation: animation)
            .playing(.fromProgress(0, toProgress: 1, loopMode: .loop))
            .frame(width: 480, height: 480)
            .accessibilityLabel("Apple Watch 제스처 안내")
            .task(id: name) {
                let loaded = await Task.detached(priority: .userInitiated) {
                    LottieAnimation.named(name)
                }.value
                guard !Task.isCancelled else { return }
                animation = loaded
            }
    }
}
