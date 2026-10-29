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
        CapturedMediaReviewView(onRetake: onRetake) { size in
            if let photo = imageStore.image {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: size.width * 0.85, maxHeight: size.height * 0.72)
                    .background(.black, in: RoundedRectangle(cornerRadius: 16))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

private final class CapturedPhotoImageStore: ObservableObject {
    let image: UIImage?

    init(data: Data) {
        image = UIImage(data: data)
    }
}
