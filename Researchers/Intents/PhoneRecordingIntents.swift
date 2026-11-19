import AppIntents
import LabcordShared

#if os(watchOS)
@MainActor
private func runRecordingAction(_ shortcut: WatchRecordingShortcut) async throws {
    try await WatchRecordingShortcutCenter.shared.performLocal(shortcut)
}
#else
@MainActor
private func runRecordingAction(_ kind: PhoneIntentRuntime.Kind) async throws {
    _ = try await PhoneIntentRuntime.shared.perform(kind)
}
#endif

struct TogglePhoneVoiceRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Watch 실험 음성 기록"
    static let description = IntentDescription(
        "Watch 실험 화면에서 음성 녹음을 시작하거나, 녹음 중이면 종료합니다."
    )
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult {
        try await runRecordingAction(.voice)
        return .result()
    }
}

struct TakePhoneExperimentPhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "Watch 실험 사진 촬영 요청"
    static let description = IntentDescription("Watch 실험 화면에서 사진 촬영을 시작합니다.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult {
        try await runRecordingAction(.photo)
        return .result()
    }
}

struct StartPhoneExperimentVideoIntent: AppIntent {
    static let persistentIdentifier = "TogglePhoneExperimentVideoIntent"
    static let title: LocalizedStringResource = "Watch 실험 영상 녹화 요청"
    static let description = IntentDescription("Watch 실험 화면에서 영상 녹화를 시작합니다.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult {
        try await runRecordingAction(.video)
        return .result()
    }
}

#if os(iOS)
struct PhoneAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TogglePhoneVoiceRecordingIntent(),
            phrases: ["\(.applicationName)에서 워치 음성 기록 전환"],
            shortTitle: "Watch 음성 기록", systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: TakePhoneExperimentPhotoIntent(),
            phrases: ["\(.applicationName)에서 아이폰으로 실험 사진 촬영"],
            shortTitle: "iPhone 사진 촬영", systemImageName: "camera.fill"
        )
        AppShortcut(
            intent: StartPhoneExperimentVideoIntent(),
            phrases: ["\(.applicationName)에서 아이폰으로 실험 영상 촬영"],
            shortTitle: "iPhone 영상 촬영", systemImageName: "video.fill"
        )
    }
}
#endif
