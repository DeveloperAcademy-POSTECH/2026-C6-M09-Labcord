import ComposableArchitecture
import LabcordiOS
import SwiftUI

struct AppView: View {
    let notificationDelegate: ForegroundNotificationDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = PhoneIntentRuntime.shared.store
    @State private var intentRuntime = PhoneIntentRuntime.shared

    var body: some View {
        @Bindable var store = store

        Group {
            if let onboardingStore = store.scope(state: \.onboarding, action: \.onboarding) {
                OnboardingView(store: onboardingStore)
            } else {
                NavigationStack(path: $store.scope(\.path, action: \.path)) {
                    HomeView(store: store.scope(state: \.home, action: \.home))
                } destination: { store in
                    switch store.case {
                    case .gestureGuide(let store):
                        GestureGuideFlowView(store: store)
                            .navigationBarBackButtonHidden()
                            .navigationSwipeBackEnabled(true)

                    case .gesturePractice(let store):
                        GesturePracticeView(
                            device: Binding(
                                get: { store.device },
                                set: { store.send(.deviceChanged($0)) }
                            ),
                            onBack: { store.send(.backTapped) },
                            onExit: { store.send(.exitTapped) }
                        )
                        .navigationBarBackButtonHidden()
                        .navigationSwipeBackEnabled(true)

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
                                    VStack {
                                        Button("정리 다시 시도") { self.store.send(.retryReviewSave) }
                                        Button("저장된 실험으로 이동") { self.store.send(.openSavedReview) }
                                    }
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
            }
        }
        .task { await store.send(.watchTask).finish() }
.task { store.send(.appeared) }
        .onAppear {
            store.send(.restoreSettingsSession)
            store.send(.watchSceneChanged(scenePhase == .active))
        }
        .onChange(of: scenePhase) { _, phase in
            store.send(.watchSceneChanged(phase == .active))
        }
        .disabled(store.reviewSaving || store.watchRequestID != nil)
        .alert("이전 Watch 음성 요청 확인", isPresented: $intentRuntime.pendingResolutionRequested) {
            Button("요청 유지", role: .cancel) { }
            Button("확인 후 해제", role: .destructive) { intentRuntime.releasePendingVoice() }
        } message: {
            Text("Watch의 녹음 상태를 직접 확인한 뒤에만 해제하세요. 이미 실행됐다면 다시 "
                 + "요청할 때 녹음이 반대로 전환될 수 있어요. 보관 원본은 삭제하지 않아요.")
        }
        .alert("요청 상태를 정리하지 못했어요", isPresented: $intentRuntime.pendingResolutionFailed) {
            Button("확인", role: .cancel) { }
        } message: {
            Text("요청은 유지돼요. 저장 공간을 확인한 뒤 다시 시도해주세요.")
        }
        .alert("실험을 저장하거나 정리하지 못했어요", isPresented: Binding(
            get: { store.reviewSaveFailed },
            set: { if !$0 { store.send(.dismissReviewSaveFailure) } }
        )) {
            Button("재시도") { store.send(.retryReviewSave) }
            if store.savedReview != nil {
                Button("저장된 실험으로 이동") { store.send(.openSavedReview) }
            }
            Button("닫기", role: .cancel) { store.send(.dismissReviewSaveFailure) }
        } message: {
            Text(store.savedReview == nil
                 ? "입력한 내용은 유지돼요. 다시 시도해 주세요."
                 : "실험은 저장됐지만 정리되지 않은 분석 파일이 남을 수 있어요.")
        }
        .alert("이미 저장된 실험이에요", isPresented: Binding(
            get: { store.reviewAlreadySaved },
            set: { if !$0 { store.send(.confirmAlreadySaved) } }
        )) {
            Button("저장된 실험으로 이동") { store.send(.confirmAlreadySaved) }
        } message: {
            Text("이 분석으로 저장한 실험이 있어요. 이번에 편집한 내용은 반영되지 않아요.")
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
        .onAppear {
            notificationDelegate.onTimerCompletionTap = { experimentID in
                store.send(.timerNotificationTapped(experimentID))
            }
            if let experimentID = notificationDelegate.takePendingExperimentID() {
                store.send(.timerNotificationTapped(experimentID))
            }
        }
        .onDisappear {
            notificationDelegate.onTimerCompletionTap = nil
        }
    }
}
