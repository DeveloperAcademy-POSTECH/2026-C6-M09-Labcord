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
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.75)

                VStack(spacing: 16) {
                    VideoPlayer(player: player)
                        .frame(
                            width: geometry.size.width * 0.85,
                            height: geometry.size.height * 0.72
                        )
                        .background(.black, in: RoundedRectangle(cornerRadius: 16))
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    if didFinishPlayback {
                        Text("3초 후 자동 저장돼요.")
                            .foregroundStyle(.white)
                    }

                    Button("다시찍기", action: onRetake)
                        .buttonStyle(.borderedProminent)
                }
                .padding(20)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
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
