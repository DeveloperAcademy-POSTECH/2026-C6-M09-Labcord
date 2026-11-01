import ComposableArchitecture
import SwiftUI

struct CameraSwitchButton: View {
    let store: StoreOf<CameraCaptureFeature>

    var body: some View {
        Button {
            store.send(.cameraSwitchRequested)
        } label: {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.body)
                .frame(width: 40, height: 40)
        }
        .foregroundStyle(.white)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(.black.opacity(0.5))
        .disabled(store.previewConnector == nil || store.isCameraSwitching)
    }
}
