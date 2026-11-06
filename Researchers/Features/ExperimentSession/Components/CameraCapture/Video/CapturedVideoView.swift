import AVKit
import Combine
import SwiftUI

struct CapturedVideoView: View {
    let onRetake: () -> Void
    let onSave: () -> Void
    let onPlaybackFinished: () -> Void
    let isSaving: Bool
    let showAutoSaveMessage: Bool

    @State private var player: AVPlayer
    @State private var playerItem: AVPlayerItem
    @State private var hasStartedPlayback = false
    @State private var didFinishPlayback = false

    init(
        videoURL: URL,
        isSaving: Bool,
        showAutoSaveMessage: Bool,
        onRetake: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onPlaybackFinished: @escaping () -> Void
    ) {
        self.onRetake = onRetake
        self.onSave = onSave
        self.onPlaybackFinished = onPlaybackFinished
        self.isSaving = isSaving
        self.showAutoSaveMessage = showAutoSaveMessage
        let item = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        _playerItem = State(initialValue: item)
        _player = State(initialValue: player)
    }

    var body: some View {
        CapturedMediaReviewView(
            onRetake: onRetake,
            onSave: onSave,
            isSaving: isSaving
        ) { size in
            VideoPlayer(player: player)
                .frame(width: size.width * 0.85, height: size.height * 0.72)
                .background(.black, in: RoundedRectangle(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if didFinishPlayback && showAutoSaveMessage {
                Text("3초 후 자동 저장돼요.")
                    .foregroundStyle(.white)
            }
        }
        .task { await startPlayback() }
        .onDisappear {
            player.pause()
            hasStartedPlayback = false
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AVPlayerItem.didPlayToEndTimeNotification,
                object: playerItem
            )
        ) { _ in
            guard !didFinishPlayback else { return }
            didFinishPlayback = true
            onPlaybackFinished()
        }
    }

    @MainActor
    private func startPlayback() async {
        guard !didFinishPlayback else { return }

        while !Task.isCancelled && !hasStartedPlayback {
            switch playerItem.status {
            case .readyToPlay:
                if player.timeControlStatus == .playing {
                    hasStartedPlayback = true
                    return
                }
                if player.timeControlStatus == .paused {
                    player.play()
                }
            case .failed:
                return
            default:
                break
            }

            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}
