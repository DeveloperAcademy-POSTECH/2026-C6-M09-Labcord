import Combine
import SwiftUI

struct CapturedPhotoView: View {
    let onRetake: () -> Void
    @StateObject private var imageStore: CapturedPhotoImageStore

    init(photoData: Data, onRetake: @escaping () -> Void) {
        self.onRetake = onRetake
        _imageStore = StateObject(wrappedValue: CapturedPhotoImageStore(data: photoData))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.75)

                VStack(spacing: 16) {
                    if let photo = imageStore.image {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                maxWidth: geometry.size.width * 0.85,
                                maxHeight: geometry.size.height * 0.72
                            )
                            .background(.black, in: RoundedRectangle(cornerRadius: 16))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    Button("다시찍기", action: onRetake)
                        .buttonStyle(.borderedProminent)
                }
                .padding(20)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }
}

private final class CapturedPhotoImageStore: ObservableObject {
    let image: UIImage?

    init(data: Data) {
        image = UIImage(data: data)
    }
}

