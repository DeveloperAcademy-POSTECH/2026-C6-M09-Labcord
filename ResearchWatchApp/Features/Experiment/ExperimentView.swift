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
    let onNavigationBlockedChanged: (Bool) -> Void
    let onPaused: () -> Void
    let onCompleted: () -> Void
    @State private var store: StoreOf<ExperimentFeature>
    @State private var selectedPage = 1
    @Binding var voiceRecording: StoreOf<VoiceRecordFeature>?
    @State private var lastVoiceDismissal: ContinuousClock.Instant?
    @Binding var photoRecording: StoreOf<PhotoRecordFeature>?
    @Binding var phoneScreen: WatchScreenSnapshot?
    @State private var videoRecording: StoreOf<VideoRecordFeature>?
    @State private var isTimerPresetPresented = false
    @State private var isAddTimerPresented = false

    private var isVoiceRecordPresented: Bool { voiceRecording != nil }
    private var isPhotoRecordPresented: Bool { photoRecording != nil }
    private var isVideoRecordPresented: Bool { videoRecording != nil }

    private var phonePhotoCountdown: WatchPhotoCountdown? {
        guard !isNavigationBlocked, store.overlay == nil, store.errorMessage == nil,
              store.closeResult == nil else { return nil }
        return WatchPhotoCountdown(screen: phoneScreen, experimentID: experiment.id)
    }

    private var isProtocolMode: Bool {
        store.snapshot?.mode == .procedure
    }

    private var isNavigationBlocked: Bool {
        isVoiceRecordPresented || isPhotoRecordPresented || isVideoRecordPresented
            || isAddTimerPresented || isTimerPresetPresented || store.isClosing
    }

    /// 프로토콜 모드는 프리셋 화면 대신 타이머 목록이 보일 때만 표시합니다.
    /// 종료된 타이머만 남아도 목록이 보이므로 버튼을 유지합니다.
    private var showsTimerAddButton: Bool {
        guard selectedPage == 2 else { return false }
        return !isProtocolMode || !store.displayedTimers.isEmpty
    }

    init(
        experiment: WatchExperimentSummary,
        voiceRecording: Binding<StoreOf<VoiceRecordFeature>?>,
        photoRecording: Binding<StoreOf<PhotoRecordFeature>?>,
        phoneScreen: Binding<WatchScreenSnapshot?>,
        onNavigationBlockedChanged: @escaping (Bool) -> Void = { _ in },
        onPaused: @escaping () -> Void,
        onCompleted: @escaping () -> Void
    ) {
        self.experiment = experiment
        self.onNavigationBlockedChanged = onNavigationBlockedChanged
        self.onPaused = onPaused
        self.onCompleted = onCompleted
        _voiceRecording = voiceRecording
        _photoRecording = photoRecording
        _phoneScreen = phoneScreen
        _store = State(initialValue: Store(
            initialState: ExperimentFeature.State(experimentID: experiment.id)
        ) {
            ExperimentFeature()
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            PhotoCountdownLabel(
                countdown: phonePhotoCountdown, fallback: selectedPage == 1 ? "실험 중" : "타이머"
            )
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color("General/Brand/Primary"))
                .padding(.bottom, WatchScreenMetrics.scaledHeight(4.5))

            ExperimentPager(selection: $selectedPage) {
                ExperimentRecordView(title: store.snapshot?.experiment.title ?? experiment.title) {
                    openVoiceRecording()
                } onPhotoRecordTap: {
                    openPhotoRecording()
                } onVideoRecordTap: {
                    openVideoRecording()
                } onPauseTap: {
                    store.send(.pauseTapped)
                } onEndTap: {
                    store.send(.endTapped)
                }
            } timers: {
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
            }
            .overlay(alignment: .bottom) {
                PageControl(pageCount: 2, selection: $selectedPage)
                    .accessibilityScrollAction { edge in
                        switch edge {
                        case .leading: selectedPage = max(1, selectedPage - 1)
                        case .trailing: selectedPage = min(2, selectedPage + 1)
                        default: break
                        }
                    }
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
            let center = WatchRecordingShortcutCenter.shared
            center.register(.experiment, in: experiment.id) { shortcut, id in
                handle(shortcut, experimentID: id)
            }
        }
        .onDisappear {
            guard !isTimerPresetPresented, !isAddTimerPresented else { return }
            store.send(.disappeared)
            shortcutLogger.info("ExperimentView disappeared")
        }
        .onChange(of: isNavigationBlocked ? nil : store.closeResult) { _, result in
            switch result {
            case .paused, .sessionUnavailable: onPaused()
            case .completed: onCompleted()
            case nil: break
            }
        }
        .onChange(of: isNavigationBlocked) { _, blocked in
            onNavigationBlockedChanged(blocked)
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
            .modifier(WatchDebugMenuModifier())
            .presentationBackground(.black)
        }
        .sheet(isPresented: Binding(
            get: { store.overlay == .end },
            set: { if !$0 { store.send(.overlayDismissed) } }
        )) {
            NavigationStack {
                EndExperimentView { store.send(.overlayDismissed) }
            }
            .modifier(WatchDebugMenuModifier())
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
        .onChange(of: isVoiceRecordPresented) { wasPresented, isPresented in
            if wasPresented && !isPresented {
                lastVoiceDismissal = .now
                WatchRecordingShortcutCenter.shared.dismissVoice(in: experiment.id)
            }
        }
        .sheet(item: $voiceRecording) { recording in
            NavigationStack {
                VoiceRecordView(store: recording, presentedRecording: $voiceRecording)
            }
            .modifier(WatchDebugMenuModifier())
            .presentationBackground(.black)
        }
        .sheet(item: $photoRecording) { photo in
            NavigationStack {
                PhotoRecordView(store: photo, presentedPhoto: $photoRecording)
            }
            .modifier(WatchDebugMenuModifier())
            .presentationBackground(.black)
        }
        .onChange(of: videoRecording) { previous, _ in
            previous?.send(.presentationEnded)
        }
        .sheet(item: $videoRecording) { video in
            NavigationStack {
                VideoRecordView(store: video, presentedVideo: $videoRecording)
            }
            .modifier(WatchDebugMenuModifier())
            .presentationBackground(.black)
        }
    }
}

private extension ExperimentView {
    func openVideoRecording() {
        guard videoRecording == nil else { return }
        let state = VideoRecordFeature.State(experimentID: experiment.id)
        let video = Store(initialState: state) { VideoRecordFeature() }
        videoRecording = video
        video.send(.openRequested)
    }

    func openPhotoRecording() {
        guard photoRecording == nil else { return }
        let state = PhotoRecordFeature.State(experimentID: experiment.id)
        let photo = Store(initialState: state) { PhotoRecordFeature() }
        photoRecording = photo
        photo.send(.openRequested)
    }

    func openVoiceRecording(resumePending: Bool = true) {
        guard voiceRecording == nil else { return }
        let state = VoiceRecordFeature.State(experimentID: experiment.id)
        let recording = Store(initialState: state) { VoiceRecordFeature() }
        voiceRecording = recording
        recording.send(.openRequested(resumePending: resumePending))
    }

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
        if shortcut == .video, let videoRecording {
            guard videoRecording.phase == .recording, !videoRecording.shouldDismiss else {
                return false
            }
            videoRecording.send(.stopTapped)
            return true
        }
        guard !isVoiceRecordPresented, !isPhotoRecordPresented, !isVideoRecordPresented,
              store.overlay == nil, store.errorMessage == nil, !store.isClosing,
              store.closeResult == nil else {
            shortcutLogger.info("Shortcut ignored: another record or overlay is presented")
            return false
        }
        if shortcut == .voice, let lastVoiceDismissal,
           lastVoiceDismissal.duration(to: .now) < .seconds(2) {
            shortcutLogger.info("Voice shortcut ignored: recently dismissed")
            return true
        }
        shortcutLogger.info("Shortcut opens \(String(describing: shortcut), privacy: .public)")
        switch shortcut {
        case .voice: openVoiceRecording(resumePending: false)
        case .photo: openPhotoRecording()
        case .video: openVideoRecording()
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
        voiceRecording: .constant(nil), photoRecording: .constant(nil),
        phoneScreen: .constant(nil),
        onPaused: {}, onCompleted: {}
    )
}
