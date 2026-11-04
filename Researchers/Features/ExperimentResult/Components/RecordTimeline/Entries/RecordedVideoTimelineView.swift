import AVKit
import SwiftUI

struct RecordedVideoTimelineView: View {
    @State private var player: AVPlayer

    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .frame(height: 160)
            .onDisappear { player.pause() }
    }
}
