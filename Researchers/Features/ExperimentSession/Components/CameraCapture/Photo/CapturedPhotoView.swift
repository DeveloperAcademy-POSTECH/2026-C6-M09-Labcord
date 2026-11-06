import Combine
import SwiftUI

struct CapturedPhotoView: View {
    let onRetake: () -> Void
    let onSave: () -> Void
    let isSaving: Bool
    @StateObject private var imageStore: CapturedPhotoImageStore

    init(
        photoData: Data,
        isSaving: Bool,
        onRetake: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self.onRetake = onRetake
        self.onSave = onSave
        self.isSaving = isSaving
        _imageStore = StateObject(wrappedValue: CapturedPhotoImageStore(data: photoData))
    }

    var body: some View {
        CapturedMediaReviewView(
            onRetake: onRetake,
            onSave: onSave,
            isSaving: isSaving
        ) { size in
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
