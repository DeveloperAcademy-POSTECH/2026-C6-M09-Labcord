import ComposableArchitecture
import LabcordDesignSystem
import LabcordShared
import LabcordWatchOS
import SwiftUI

struct ExperimentView: View {
    let experiment: WatchExperimentSummary
    let onPaused: () -> Void
    let onCompleted: () -> Void
    @State private var store: StoreOf<ExperimentFeature>
    @State private var selectedPage = 1
    @Binding var isVoiceRecordPresented: Bool
    @State private var isPhotoRecordPresented = false
    @State private var isVideoRecordPresented = false

    private var showsTimerAddButton: Bool {
        guard selectedPage == 2 else { return false }
        return store.snapshot?.mode != .procedure ||
            store.snapshot?.timers.contains { $0.status == .running } == true
    }

    init(
        experiment: WatchExperimentSummary,
        isVoiceRecordPresented: Binding<Bool>,
        onPaused: @escaping () -> Void,
        onCompleted: @escaping () -> Void
    ) {
        self.experiment = experiment
        self.onPaused = onPaused
        self.onCompleted = onCompleted
        _isVoiceRecordPresented = isVoiceRecordPresented
        _store = State(initialValue: Store(
            initialState: ExperimentFeature.State(experimentID: experiment.id)
        ) {
            ExperimentFeature()
        })
    }

    var body: some View {
        VStack {
            Text(selectedPage == 1 ? "실험 중" : "타이머")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color("General/Brand/Primary"))
                .padding(.bottom, WatchScreenMetrics.scaledHeight(4.5))

            TabView(selection: $selectedPage) {
                ExperimentRecordView(title: experiment.title) {
                    isVoiceRecordPresented = true
                } onPhotoRecordTap: {
                    isPhotoRecordPresented = true
                } onVideoRecordTap: {
                    isVideoRecordPresented = true
                } onPauseTap: {
                    store.send(.pauseTapped)
                } onEndTap: {
                    store.send(.endTapped)
                }
                    .tag(1)

                ExperimentTimerView(
                    mode: store.snapshot?.mode,
                    timers: store.snapshot?.timers ?? [],
                    protocolTimerSeconds: store.snapshot?.protocolTimerSeconds ?? []
                )
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .overlay(alignment: .bottom) {
                PageControl(pageCount: 2, selection: $selectedPage)
            }
        }
        .padding(.top, WatchScreenMetrics.scaledHeight(24.5))
        .padding(.horizontal, 6)
        .ignoresSafeArea()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if showsTimerAddButton {
                    Button {} label: {
                        Image(systemName: "plus")
                    }
                } else {
                    Color.clear
                        .frame(width: 1, height: 1)
                }
            }
        }
        .onAppear { store.send(.appeared) }
        .onDisappear { store.send(.disappeared) }
        .onChange(of: store.closeResult) { _, result in
            switch result {
            case .paused: onPaused()
            case .completed: onCompleted()
            case nil: break
            }
        }
        .sheet(isPresented: Binding(
            get: { store.overlay == .stop },
            set: { if !$0 { store.send(.overlayDismissed) } }
        )) {
            NavigationStack {
                StopExperimentView(
                    onStop: { store.send(.stopConfirmed) },
                    onCancel: { store.send(.overlayDismissed) }
                )
            }
            .presentationBackground(.black)
        }
        .sheet(isPresented: Binding(
            get: { store.overlay == .end },
            set: { if !$0 { store.send(.overlayDismissed) } }
        )) {
            NavigationStack {
                EndExperimentView(onCancel: { store.send(.overlayDismissed) })
            }
            .presentationBackground(.black)
        }
        .alert("실험을 변경하지 못했어요", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.send(.overlayDismissed) } }
        )) {
            Button("확인", role: .cancel) { store.send(.overlayDismissed) }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .sheet(isPresented: $isVoiceRecordPresented) {
            NavigationStack {
                VoiceRecordView(experimentID: experiment.id)
            }
            .presentationBackground(.black)
        }
        .sheet(isPresented: $isPhotoRecordPresented) {
            NavigationStack {
                PhotoRecordView(experimentID: experiment.id)
            }
            .presentationBackground(.black)
        }
        .sheet(isPresented: $isVideoRecordPresented) {
            NavigationStack {
                VideoRecordView(experimentID: experiment.id)
            }
            .presentationBackground(.black)
        }
    }
}

#Preview {
    ExperimentView(
        experiment: WatchExperimentSummary(
            id: UUID(),
            title: "새 실험(1)",
            status: .running
        ),
        isVoiceRecordPresented: .constant(false),
        onPaused: {}, onCompleted: {}
    )
}
