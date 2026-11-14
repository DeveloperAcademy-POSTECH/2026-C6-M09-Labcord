import ComposableArchitecture
import SwiftUI
import UIKit

struct PhotoAccessAlert: ViewModifier {
    let store: StoreOf<ProtocolRegistrationFeature>
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.alert("사진 접근을 허용해 주세요", isPresented: Binding(
            get: { store.photoAccessIssue != nil },
            set: { if !$0 { store.send(.dismissPhotoAccessIssue) } }
        )) {
            if store.photoAccessIssue == .denied {
                Button("설정으로 이동") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else {
                        return
                    }
                    openURL(url)
                }
            }
            Button("확인", role: .cancel) { store.send(.dismissPhotoAccessIssue) }
        } message: {
            if store.photoAccessIssue == .denied {
                Text("사진을 추가하려면 설정에서 사진 접근을 허용해 주세요.")
            } else {
                Text("이 기기에서는 사진 보관함 접근이 제한되어 있어요.")
            }
        }
    }
}
