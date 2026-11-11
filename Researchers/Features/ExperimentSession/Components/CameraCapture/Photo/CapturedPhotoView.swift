import Combine
import SwiftUI

struct CapturedPhotoView: View {
    let onRetake: () -> Void
    let onClose: () -> Void
    let onSave: () -> Void
    let isSaving: Bool
    @StateObject private var imageStore: CapturedPhotoImageStore

    init(
        photoData: Data,
        isSaving: Bool,
        onRetake: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self.onRetake = onRetake
        self.onClose = onClose
        self.onSave = onSave
        self.isSaving = isSaving
        _imageStore = StateObject(wrappedValue: CapturedPhotoImageStore(data: photoData))
    }

    var body: some View {
        CapturedMediaReviewView(
            title: "사진 기록",
            onRetake: onRetake,
            onClose: onClose,
            onSave: onSave,
            isSaving: isSaving,
            isCloseEnabled: !isSaving
        ) {
            if let photo = imageStore.image {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
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
