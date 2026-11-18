import AppIntents

struct ToggleWatchVoiceRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Watch 실험 음성 녹음"
    static let description = IntentDescription(
        "실험 중 Watch 음성 녹음을 시작하거나, 녹음 중이면 종료합니다."
    )
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchRecordingShortcutCenter.shared.send(.voice)
        return .result()
    }
}

struct TakeWatchExperimentPhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "Watch 실험 사진 촬영"
    static let description = IntentDescription("실험 중 Watch에서 사진 촬영을 요청합니다.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchRecordingShortcutCenter.shared.send(.photo)
        return .result()
    }
}

struct StartWatchExperimentVideoIntent: AppIntent {
    static let title: LocalizedStringResource = "Watch 실험 영상 녹화"
    static let description = IntentDescription("실험 중 Watch에서 영상 녹화를 시작합니다.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchRecordingShortcutCenter.shared.send(.video)
        return .result()
    }
}

struct WatchAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleWatchVoiceRecordingIntent(),
            phrases: ["\(.applicationName)에서 음성 녹음"],
            shortTitle: "음성 녹음", systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: TakeWatchExperimentPhotoIntent(),
            phrases: ["\(.applicationName)에서 사진 촬영"],
            shortTitle: "사진 촬영", systemImageName: "camera.fill"
        )
        AppShortcut(
            intent: StartWatchExperimentVideoIntent(),
            phrases: ["\(.applicationName)에서 영상 녹화"],
            shortTitle: "영상 녹화", systemImageName: "video.fill"
        )
    }
}
