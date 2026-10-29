import AVKit
import Combine
import SwiftUI

struct CapturedVideoView: View {
    let onRetake: () -> Void
    @State private var player: AVPlayer
    @State private var playerItem: AVPlayerItem
    @State private var hasStartedPlayback = false
    @State private var didFinishPlayback = false

    init(videoURL: URL, onRetake: @escaping () -> Void) {
        self.onRetake = onRetake
        let item = AVPlayerItem(url: videoURL)
        _playerItem = State(initialValue: item)
        _player = State(initialValue: AVPlayer(playerItem: item))
    }

    var body: some View {
        CapturedMediaReviewView(onRetake: onRetake) { size in
            VideoPlayer(player: player)
                .frame(width: size.width * 0.85, height: size.height * 0.72)
                .background(.black, in: RoundedRectangle(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if didFinishPlayback {
                Text("3초 후 자동 저장돼요.")
                    .foregroundStyle(.white)
            }
        }
        .onAppear { startPlayback() }
        .onDisappear {
            player.pause()
            hasStartedPlayback = false
        }
        .onReceive(playerItem.publisher(for: \.status, options: [.initial, .new])) { status in
            if status == .readyToPlay {
                startPlayback()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AVPlayerItem.didPlayToEndTimeNotification,
                object: playerItem
            )
        ) { _ in
            didFinishPlayback = true
        }
    }

    private func startPlayback() {
        guard playerItem.status == .readyToPlay, !hasStartedPlayback else { return }
        hasStartedPlayback = true
        didFinishPlayback = false
        player.seek(to: .zero)
        player.play()
    }
}
