import AppIntents

struct WatchAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleWatchVoiceRecordingIntent(),
            phrases: ["\(.applicationName)에서 음성 기록 전환"],
            shortTitle: "음성 기록",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: TakeWatchPhotoIntent(),
            phrases: ["\(.applicationName)에서 실험 사진 촬영"],
            shortTitle: "사진 촬영",
            systemImageName: "camera.fill"
        )
        AppShortcut(
            intent: ToggleWatchVideoRecordingIntent(),
            phrases: ["\(.applicationName)에서 영상 기록 전환"],
            shortTitle: "영상 기록",
            systemImageName: "video.fill"
        )
    }
}
