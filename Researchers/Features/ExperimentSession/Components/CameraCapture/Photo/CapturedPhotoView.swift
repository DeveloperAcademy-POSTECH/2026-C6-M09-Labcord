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
            title: "사진 기록",
            onRetake: onRetake,
            onClose: onRetake,
            onSave: onSave,
            isSaving: isSaving,
            isCloseEnabled: !isSaving
        ) { size in
            if let photo = imageStore.image {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: size.width * 370 / 402,
                        height: size.height * 683 / 874
                    )
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
