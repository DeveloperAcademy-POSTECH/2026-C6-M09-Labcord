import ComposableArchitecture
import LabcordiOS
import SwiftUI

struct AppView: View {
    @State private var store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    var body: some View {
        @Bindable var store = store

        NavigationStack(path: $store.scope(\.path, action: \.path)) {
            HomeView(store: store.scope(state: \.home, action: \.home))
        } destination: { store in
            switch store.case {
            case .registration(let store):
                ProtocolRegistrationView(store: store)
                    .navigationSwipeBackEnabled(!store.isSaving)

            case .recent(let store):
                RecentProtocolView(store: store)

            case .review(let store):
                ProtocolReviewView(store: store)
                    .disabled(self.store.savedReview != nil)
                    .overlay(alignment: .bottom) {
                        if self.store.savedReview != nil {
                            Button("정리 다시 시도") { self.store.send(.retryReviewSave) }
                                .padding()
                                .background(.regularMaterial, in: Capsule())
                                .padding()
                        }
                    }
                    .navigationSwipeBackEnabled(false)

            case .session(let store):
                ExperimentSessionView(store: store)
                    .navigationSwipeBackEnabled(false)

            case .result(let store):
                ExperimentResultView(store: store)
                    .navigationSwipeBackEnabled(store.isOpenedFromHome)
            }
        }
        .disabled(store.reviewSaving)
        .alert("실험을 저장하거나 정리하지 못했어요", isPresented: Binding(
            get: { store.reviewSaveFailed },
            set: { if !$0 { store.send(.dismissReviewSaveFailure) } }
        )) {
            Button("재시도") { store.send(.retryReviewSave) }
            Button("닫기", role: .cancel) { store.send(.dismissReviewSaveFailure) }
        } message: {
            Text("입력한 내용은 유지돼요. 다시 시도해 주세요.")
        }
        .alert("결과 편집을 종료할까요?", isPresented: Binding(
            get: { store.reviewExitRequested },
            set: { if !$0 { store.send(.cancelReviewExit) } }
        )) {
            Button("계속 편집", role: .cancel) { store.send(.cancelReviewExit) }
            Button("종료", role: .destructive) { store.send(.confirmReviewExit) }
        } message: {
            Text("편집한 내용은 저장되지 않아요.")
        }
    }
}
