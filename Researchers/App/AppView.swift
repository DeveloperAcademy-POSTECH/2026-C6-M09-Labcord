import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct AppView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = PhoneIntentRuntime.shared.store

    private var showsLocalRecording: Bool {
        guard let id = store.path.ids.last,
              let session = store.path[id: id, case: \.session] else { return false }
        if session.voice.phase != .hidden || session.voice.hasRecordingFailure { return true }
        switch session.capture.video.phase {
        case .starting, .recording: return true
        case .idle, .preview: return false
        }
    }

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
                            store: store,
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
                            .navigationSwipeBackEnabled(
                                !store.isSaving && store.inputAnalysis.analysisID == nil
                                    && !store.inputAnalysis.showsAnalysisCompletion
                                    && !store.inputAnalysis.analysisStarting
                            )

                    case .recent(let store):
                        RecentProtocolView(store: store)
                            .navigationSwipeBackEnabled(true)

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
                            .navigationSwipeBackEnabled(
                                store.isOpenedFromHome && !store.isResuming
                            )
                    }
                }
                .onChange(of: store.path.ids.last) { _, _ in
                    SessionOrientation.reset()
                }
            }
        }
        .overlay {
            if store.onboarding == nil, !showsLocalRecording {
                WatchVoiceLiveActivityOverlay()
            }
        }
        .preferredColorScheme(
            store.path.ids.last.map { store.path[id: $0, case: \.gesturePractice] != nil } == true
                ? .dark : .light
        )
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
        .alert(store.reviewReturningToAnalysis ? "분석 화면으로 돌아갈까요?" : "실험 등록을 종료할까요?",
               isPresented: Binding(
            get: { store.reviewExitRequested },
            set: { if !$0 { store.send(.cancelReviewExit) } }
        )) {
            Button("취소", role: .cancel) { store.send(.cancelReviewExit) }
            Button(store.reviewReturningToAnalysis ? "돌아가기" : "실험 등록 종료", role: .destructive) {
                store.send(.confirmReviewExit)
            }
        } message: {
            Text(store.reviewReturningToAnalysis
                 ? "이 화면에서 수정한 내용은 저장되지 않아요."
                 : "이 화면을 나가면 분석 결과가 초기화 돼요.")
        }
    }
}

private struct WatchVoiceLiveActivityOverlay: View {
    @State private var isRecordingVisible = false
    private var recording: PhoneWatchAudioService.LiveRecording? {
        PhoneWatchAudioService.shared.liveRecording
    }

    var body: some View {
        GeometryReader { geometry in
            if isRecordingVisible, recording != nil {
                AnimatedLiveActivityContainer(
                    isExpanded: true,
                    collapsedSize: CGSize(width: 125, height: 37),
                    expandedWidth: max(0, geometry.size.width - 2 * LayoutTokens.spacing16),
                    minimumContentHeight: 52,
                    animatesContentHeight: false
                ) {
                    LiveActivityContent(state: .watchAudioRecording, onStop: {}, onRetry: {})
                }
                .padding(.top, 14)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .allowsHitTesting(false)
        .task(id: recording) {
            guard let recording, recording.expiresAt > .now else {
                isRecordingVisible = false
                return
            }
            isRecordingVisible = true
            let remaining = max(0, recording.expiresAt.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            isRecordingVisible = false
        }
    }
}
