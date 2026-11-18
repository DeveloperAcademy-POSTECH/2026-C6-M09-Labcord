import ComposableArchitecture
import LabcordDesignSystem
import LabcordShared
import LabcordWatchOS
import OSLog
import SwiftUI

private let shortcutLogger = Logger(
    subsystem: "com.researchers.Researchers.watchkitapp", category: "WatchShortcut"
)

struct ExperimentView: View {
    let experiment: WatchExperimentSummary
    let onPaused: () -> Void
    let onCompleted: () -> Void
    @State private var store: StoreOf<ExperimentFeature>
    @State private var selectedPage = 1
    @Binding var isVoiceRecordPresented: Bool
    @State private var isPhotoRecordPresented = false
    @State private var isVideoRecordPresented = false
    @State private var shortcutRegistration: WatchRecordingShortcutCenter.Registration?
    @State private var isTimerPresetPresented = false
    @State private var isAddTimerPresented = false

    private var isProtocolMode: Bool {
        store.snapshot?.mode == .procedure
    }

    /// 프로토콜 모드는 프리셋 화면 대신 타이머 목록이 보일 때만 표시합니다.
    /// 종료된 타이머만 남아도 목록이 보이므로 버튼을 유지합니다.
    private var showsTimerAddButton: Bool {
        guard selectedPage == 2 else { return false }
        return !isProtocolMode || !store.displayedTimers.isEmpty
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
                    timers: store.displayedTimers,
                    protocolTimerSeconds: store.snapshot?.protocolTimerSeconds ?? [],
                    pendingTimerIDs: store.pendingTimerIDs.union(
                        store.syncingTimerID.map { Set([$0]) } ?? []
                    ),
                    creatingTimerIDs: Set(store.localTimers.map(\.id)),
                    onTimerCommand: { id, operation in
                        store.send(.timerCommandTapped(id, operation))
                    },
                    onStartTimer: { seconds in
                        store.send(.timerStartTapped(seconds))
                    },
                    onAddTimer: { isAddTimerPresented = true }
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
                    Button {
                        if isProtocolMode {
                            isTimerPresetPresented = true
                        } else {
                            isAddTimerPresented = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                } else {
                    Color.clear
                        .frame(width: 1, height: 1)
                }
            }
        }
        .navigationDestination(isPresented: $isTimerPresetPresented) {
            SettingTimerScreen(
                timerSeconds: store.snapshot?.protocolTimerSeconds ?? [],
                canAddTimer: store.canAddTimer
            ) { seconds in
                store.send(.timerStartTapped(seconds))
                returnToTimerList()
            } onCustomStart: { seconds in
                store.send(.customTimerStartTapped(seconds))
                returnToTimerList()
            }
        }
        .navigationDestination(isPresented: $isAddTimerPresented) {
            AddTimerView(canAddTimer: store.canAddTimer) { seconds in
                store.send(.customTimerStartTapped(seconds))
                returnToTimerList()
            }
        }
        .onAppear {
            store.send(.appeared)
            shortcutLogger.info("ExperimentView appeared")
            if shortcutRegistration == nil {
                let center = WatchRecordingShortcutCenter.shared
                shortcutRegistration = center.register { shortcut, id in
                    handle(shortcut, experimentID: id)
                }
            }
        }
        .onDisappear {
            guard !isTimerPresetPresented, !isAddTimerPresented else { return }
            store.send(.disappeared)
            shortcutLogger.info("ExperimentView disappeared")
        }
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
                EndExperimentView { store.send(.overlayDismissed) }
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

private extension ExperimentView {
    /// 타이머를 시작한 하위 화면을 모두 닫고 타이머 탭에서 실행 중인 타이머를 보여 줍니다.
    func returnToTimerList() {
        selectedPage = 2
        isTimerPresetPresented = false
        isAddTimerPresented = false
    }

    /// 기록 버튼을 누른 것과 같은 흐름으로 단축어를 처리합니다.
    /// 다른 기록 화면이나 확인창이 떠 있으면 무시하며,
    /// 열린 음성 녹음 화면의 종료 요청은 VoiceRecordView가 처리합니다.
    func handle(_ shortcut: WatchRecordingShortcut, experimentID: UUID?) -> Bool {
        guard experimentID == nil || experimentID == experiment.id else { return false }
        guard !isVoiceRecordPresented, !isPhotoRecordPresented, !isVideoRecordPresented,
              store.overlay == nil, store.errorMessage == nil, !store.isClosing,
              store.closeResult == nil else {
            shortcutLogger.info("Shortcut ignored: another record or overlay is presented")
            return false
        }
        shortcutLogger.info("Shortcut opens \(String(describing: shortcut), privacy: .public)")
        switch shortcut {
        case .voice: isVoiceRecordPresented = true
        case .photo: isPhotoRecordPresented = true
        case .video: isVideoRecordPresented = true
        }
        return true
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
