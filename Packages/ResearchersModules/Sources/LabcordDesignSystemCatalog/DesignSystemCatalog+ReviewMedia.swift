import LabcordDesignSystem
import SwiftUI
#if os(iOS)
import AVKit
import UIKit
#endif

struct CatalogSampleMedia: View {
    var isVideo = false

    var body: some View {
        GeometryReader { geometry in
            #if os(iOS)
            if let image = cachedImage {
                scaledImage(Image(uiImage: image), size: geometry.size)
            } else {
                missingImage
            }
            #else
            scaledImage(
                Image(resourceName + ".jpg", bundle: Bundle.module),
                size: geometry.size
            )
            #endif
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityName))
    }

    private var resourceName: String {
        isVideo ? "catalog-example-video-poster" : "catalog-example-photo"
    }

    private var accessibilityName: String {
        #if os(iOS)
        if cachedImage == nil { return "샘플 이미지를 불러올 수 없어요" }
        #endif
        return isVideo ? "예시 영상 포스터" : "예시 실험 사진"
    }

    private func scaledImage(_ image: Image, size: CGSize) -> some View {
        image
            .renderingMode(.original)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
    }

    private var missingImage: some View {
        Text("샘플 이미지를 불러올 수 없어요")
            .font(.caption)
            .foregroundStyle(.labcord(.labelSecondary))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.labcord(.fillTertiary))
    }

    #if os(iOS)
    private var cachedImage: UIImage? {
        isVideo ? CatalogSampleImageCache.videoPoster : CatalogSampleImageCache.photo
    }
    #endif
}

#if os(iOS)
@MainActor
private enum CatalogSampleImageCache {
    static let photo = load("catalog-example-photo")
    static let videoPoster = load("catalog-example-video-poster")

    private static func load(_ name: String) -> UIImage? {
        guard let url = Bundle.module.url(
            forResource: name, withExtension: "jpg"
        ) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)?.withRenderingMode(.alwaysOriginal)
    }
}
#endif

struct CatalogLoopingVideo: View {
    #if os(iOS)
    @State private var playback = CatalogVideoPlayback()
    @Environment(\.scenePhase) private var scenePhase
    #endif

    var body: some View {
        #if os(iOS)
        VideoPlayer(player: playback.player)
            .overlay(alignment: .topLeading) {
                Text("로컬 반복 재생 데모")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(8)
                    .allowsHitTesting(false)
            }
            .aspectRatio(370.0 / 201.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onAppear { playback.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { playback.resume() } else { playback.suspend() }
            }
            .onDisappear { playback.stop() }
            .accessibilityIdentifier("catalog.review.video.looping")
        #else
        CatalogSampleMedia(isVideo: true)
            .overlay(alignment: .bottom) {
                Text("영상 재생 데모는 iOS에서 확인할 수 있어요")
                    .typography(Typography.footnote)
            }
        #endif
    }
}

#if os(iOS)
@MainActor
private final class CatalogVideoPlayback {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var resumesAfterInterruption: Bool?

    func start() {
        guard looper == nil, let url = Bundle.module.url(
            forResource: "catalog-video-demo", withExtension: "mp4"
        ) else {
            return
        }
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.isMuted = true
        player.play()
    }

    func suspend() {
        if resumesAfterInterruption == nil { resumesAfterInterruption = player.rate > 0 }
        player.pause()
    }

    func resume() {
        guard let shouldResume = resumesAfterInterruption else { return }
        resumesAfterInterruption = nil
        if shouldResume { player.play() }
    }

    func stop() {
        player.pause()
        resumesAfterInterruption = nil
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
    }
}
#endif

struct CatalogTextEditor: View {
    @Binding var value: String
    @FocusState private var isFocused: Bool

    var body: some View {
#if os(watchOS)
        Text(value.isEmpty ? "내용을 입력해 주세요" : value)
            .typography(Typography.subheadline)
            .foregroundStyle(.labcord(value.isEmpty ? .labelTertiary : .labelPrimary))
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(12)
            .background(.labcord(.backgroundGroupedSecondary))
        #else
        TextEditor(text: $value)
            .labcordTextEditorStyle(
                text: value,
                focus: $isFocused,
                placeholder: Text("내용을 입력해 주세요")
            )
            .accessibilityLabel(Text("메모"))
        #endif
    }
}

#Preview("미디어 예제") {
    VStack(spacing: 16) {
        CatalogSampleMedia()
        CatalogSampleMedia(isVideo: true)
    }
    .padding()
}
