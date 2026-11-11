import AVKit
import Combine
import SwiftUI

struct CapturedVideoView: View {
    let onRetake: () -> Void
    let onClose: () -> Void
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
        onClose: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onPlaybackFinished: @escaping () -> Void
    ) {
        self.onRetake = onRetake
        self.onClose = onClose
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
            title: "영상 기록",
            onRetake: onRetake,
            onClose: onClose,
            onSave: onSave,
            isSaving: isSaving,
            showsAutoSaveNotice: didFinishPlayback && showAutoSaveMessage
        ) { size in
            VideoPlayer(player: player)
                .scaledToFill()
                .frame(
                    width: size.width * 370 / 402,
                    height: size.height * 683 / 874
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

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
