import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import LabcordShared
import SwiftUI

@main
struct ResearchersApp: App {
    @UIApplicationDelegateAdaptor(OrientationAppDelegate.self) private var orientationDelegate

    @State private var isSplashActive = true
    #if DEBUG && targetEnvironment(simulator)
    @State private var resetError: String?
    #endif

    init() {
        #if DEBUG && targetEnvironment(simulator)
        do {
            if !ProcessInfo.processInfo.arguments.contains(
                "-LabcordPreserveSimulatorExperiments"
            ) {
                try RecordingDemoSeeder().resetSimulatorExperiments()
            }
            _resetError = State(initialValue: nil)
        } catch {
            _resetError = State(initialValue: error.localizedDescription)
            FontRegistration.register()
            return
        }
        #endif
        PhoneWatchExperimentCoordinator.shared.activate()
        PhoneWatchAudioService.shared.activate()
        PhoneWatchExperimentCoordinator.shared.configureRecordHandling()
        FontRegistration.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let resetError {
                    Text("시뮬레이터 실험 초기화 실패: \(resetError)")
                } else if isSplashActive {
                    SplashView()
                        .preferredColorScheme(.light)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                withAnimation {
                                    self.isSplashActive = false
                                }
                            }
                        }
                } else {
                    AppView()
                }
            }
            #if DEBUG && targetEnvironment(simulator)
            .overlay(alignment: .bottomLeading) {
                if ProcessInfo.processInfo.arguments.contains("-LabcordWatchActionTest") {
                    WatchActionTestControls()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                RecordingDemoVideoControls()
            }
            .overlay(alignment: .bottom) {
                RecordingDemoResultControls()
            }
            #endif
            .onOpenURL { url in
                guard let experimentID = ExperimentLiveActivityURL.experimentID(from: url)
                else { return }
                Task { @MainActor in
                    PhoneIntentRuntime.shared.store.send(.openLiveActivityExperiment(experimentID))
                }
            }
        }
    }

    #if !DEBUG || !targetEnvironment(simulator)
    private var resetError: String? { nil }
    #endif
}

#if DEBUG && targetEnvironment(simulator)
private struct RecordingDemoResultControls: View {
    @State private var state = "시연 결과 준비"
    @State private var isPreparing = false
    @State private var errorMessage: String?

    var body: some View {
        Button(state) {
            isPreparing = true
            state = "시연 결과 준비 중"
            Task { @MainActor in
                do {
                    guard RecordingDemoSeeder.isRequested else {
                        throw RecordingDemoSeeder.SeedError.missingDirectory
                    }
                    try await RecordingDemoSeeder().runIfRequested()
                    PhoneIntentRuntime.shared.store.send(.home(.list(.load)))
                    state = "시연 결과 준비 완료"
                } catch {
                    state = "시연 결과 준비"
                    errorMessage = error.localizedDescription
                }
                isPreparing = false
            }
        }
        .font(.caption2)
        .padding(4)
        .foregroundStyle(.clear)
        .disabled(isPreparing)
        .alert("시연 결과 준비 실패", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

private struct RecordingDemoVideoControls: View {
    @State private var isPresented = false
    @State private var pendingURL: URL?
    @State private var hasPendingSelection = false

    private let videos = [
        "V03", "V04", "V05", "V06-A", "V07", "V08", "V12",
        "W01_ready", "W05_phone_capture"
    ]

    var body: some View {
        Button("영상 선택") { isPresented = true }
            .font(.caption2)
            .padding(4)
            .foregroundStyle(.clear)
            .sheet(isPresented: $isPresented, onDismiss: {
                guard hasPendingSelection else { return }
                RecordingDemoVideoPreview.select(url: pendingURL)
                hasPendingSelection = false
            }, content: {
                VStack(spacing: 16) {
                    ForEach(videos, id: \.self) { video in
                        Button("\(video) 재생") {
                            pendingURL = videoURL(video)
                            hasPendingSelection = true
                            isPresented = false
                        }
                        .disabled(!FileManager.default.fileExists(atPath: videoURL(video).path))
                    }
                    Button("초록 화면") {
                        pendingURL = nil
                        hasPendingSelection = true
                        isPresented = false
                    }
                    Button("닫기") { isPresented = false }
                }
            })
    }

    private func videoURL(_ video: String) -> URL {
        let fileName = [
            "V06-A": "W02_double_pinch", "V07": "W03_single_fist", "V08": "W04_double_fist"
        ][video] ?? video
        return URL.documentsDirectory.appending(path: "LabcordDemoVideos")
            .appending(path: "\(fileName).mp4")
    }
}

private struct WatchActionTestControls: View {
    @State private var isPresented = false
    @State private var status = "대기"
    @State private var requestID: UUID?
    @State private var pendingAction: String?

    private let actions = ["audio", "photo", "video"]

    var body: some View {
        Button("Watch 테스트") { isPresented = true }
            .font(.caption2)
            .padding(4)
            .foregroundStyle(.clear)
            .sheet(isPresented: $isPresented, onDismiss: {
                guard let action = pendingAction else { return }
                pendingAction = nil
                send(action)
            }, content: {
                VStack(spacing: 16) {
                    Text(status).accessibilityIdentifier("watch-action-test-status")
                    ForEach(actions, id: \.self) { action in
                        Button("Watch 테스트 \(action)") {
                            pendingAction = action
                            isPresented = false
                        }
                            .disabled(requestID != nil)
                    }
                    Button("닫기") { isPresented = false }
                }
                .padding()
            })
    }

    private func send(_ action: String) {
        let id = UUID()
        requestID = id
        status = "Watch 처리 대기 \(action)"
        PhoneWatchExperimentCoordinator.shared.sendWatchActionTest(action) { succeeded in
            guard requestID == id else { return }
            requestID = nil
            status = "Watch \(succeeded ? "처리 완료" : "실패") \(action)"
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            guard requestID == id else { return }
            requestID = nil
            status = "Watch 응답 시간 초과 \(action)"
        }
    }
}
#endif
