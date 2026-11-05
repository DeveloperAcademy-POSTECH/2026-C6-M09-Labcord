import AVFoundation
import SwiftUI

struct RecordedVideoTimelineView: View {
    @State private var player: AVPlayer
    @State private var previewAspectRatio: CGFloat = 16.0 / 9.0

    private let url: URL

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        AspectFillVideoView(player: player)
            .aspectRatio(previewAspectRatio, contentMode: .fit)
            .task(id: url) {
                let asset = AVURLAsset(url: url)
                guard let tracks = try? await asset.loadTracks(withMediaType: .video),
                      let track = tracks.first,
                      let size = try? await track.load(.naturalSize),
                      let transform = try? await track.load(.preferredTransform) else {
                    return
                }

                let displayedSize = size.applying(transform)
                previewAspectRatio = abs(displayedSize.height) > abs(displayedSize.width)
                    ? 3.0 / 4.0 : 16.0 / 9.0
            }
            .onDisappear { player.pause() }
    }
}

struct AspectFillVideoView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = PlayerView()
        view.playerLayer?.player = player
        view.playerLayer?.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView.layer as? AVPlayerLayer)?.player = player
    }
}

private final class PlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
}
