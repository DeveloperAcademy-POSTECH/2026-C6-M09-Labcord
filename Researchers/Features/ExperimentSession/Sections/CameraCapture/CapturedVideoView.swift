import AVKit
import Combine
import SwiftUI

struct CapturedVideoView: View {
    let onRetake: () -> Void
    @State private var player: AVPlayer
    @State private var didFinishPlayback = false

    init(videoURL: URL, onRetake: @escaping () -> Void) {
        self.onRetake = onRetake
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        CapturedMediaLayout(onRetake: onRetake) { size in
            VideoPlayer(player: player)
                .frame(width: size.width * 0.85, height: size.height * 0.72)
                .background(.black, in: RoundedRectangle(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if didFinishPlayback {
                Text("3초 후 자동 저장돼요.")
                    .foregroundStyle(.white)
            }
        }
        .onAppear { player.play() }
        .onDisappear { player.pause() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AVPlayerItem.didPlayToEndTimeNotification,
                object: player.currentItem
            )
        ) { _ in
            didFinishPlayback = true
        }
    }
}
