import ComposableArchitecture
import SwiftUI

struct WatchGesturePracticeView: View {
    let store: StoreOf<WatchExperimentFeature>

    var body: some View {
        VStack(spacing: 8) {
            Text("제스처 안내")
                .font(.headline)
            Text("음성 녹음: 엄지와 검지를 빠르게 두 번 탭")
            Text("사진 촬영: 주먹 한 번 쥐기")
            Text("영상 녹화: 주먹 빠르게 두 번 쥐기")
            Button("닫기") { store.send(.closeTapped) }
        }
        .font(.caption)
    }
}
