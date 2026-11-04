import Foundation
import ImageIO
import SwiftUI

struct ProtocolPhotoThumbnail: View {
    let url: URL
    @State private var thumbnail: CGImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(thumbnail, scale: 1, label: Text("선택한 사진"))
                    .resizable().scaledToFill()
            } else {
                ProgressView()
            }
        }
        .accessibilityLabel("선택한 사진")
        .task(id: url) {
            thumbnail = await Self.loadThumbnail(url)
        }
    }

    private static func loadThumbnail(_ url: URL) async -> CGImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 300
                ]
                let source = CGImageSourceCreateWithURL(url as CFURL, nil)
                let image = source.flatMap {
                    CGImageSourceCreateThumbnailAtIndex($0, 0, options as CFDictionary)
                }
                continuation.resume(returning: image)
            }
        }
    }
}
