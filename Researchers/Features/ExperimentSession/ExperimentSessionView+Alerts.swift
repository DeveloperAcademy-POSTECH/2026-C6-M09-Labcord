import ComposableArchitecture
import SwiftUI

struct DetailLoadFailureAlert: ViewModifier {
    let store: StoreOf<ExperimentSessionFeature>

    func body(content: Content) -> some View {
        content.alert("실험 정보를 불러오지 못했어요", isPresented: Binding(
            get: { store.detailLoadFailed },
            set: { if !$0 { store.send(.dismissDetailLoadFailure) } }
        )) {
            Button("다시 시도") { store.send(.loadDetail) }
            Button("닫기", role: .cancel) { store.send(.dismissDetailLoadFailure) }
        } message: {
            Text("실험 정보를 불러온 뒤 녹음할 수 있어요.")
        }
    }
}

#Preview {
    ExperimentSessionView(
        store: Store(
            initialState: ExperimentSessionFeature.State(
                experimentID: UUID()
            )
        ) {
            ExperimentSessionFeature()
        }
    )
}
