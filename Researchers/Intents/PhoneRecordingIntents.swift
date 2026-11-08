import AppIntents

struct TogglePhoneVoiceRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Watch 실험 음성 기록"
    static let description = IntentDescription("현재 실험의 Watch 음성 기록을 요청합니다.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await PhoneIntentRuntime.shared.perform(.voice)
        return .result(dialog: "\(message)")
    }
}

struct TakePhoneExperimentPhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "iPhone 실험 사진 촬영"
    static let description = IntentDescription("현재 실험에서 카메라로 사진을 촬영합니다.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await PhoneIntentRuntime.shared.perform(.photo)
        return .result(dialog: "\(message)")
    }
}

struct TogglePhoneExperimentVideoIntent: AppIntent {
    static let title: LocalizedStringResource = "iPhone 실험 영상 녹화 시작"
    static let description = IntentDescription("현재 실험에서 카메라로 영상 녹화를 시작합니다.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await PhoneIntentRuntime.shared.perform(.video)
        return .result(dialog: "\(message)")
    }
}

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
            intent: TogglePhoneExperimentVideoIntent(),
            phrases: ["\(.applicationName)에서 아이폰으로 실험 영상 촬영"],
            shortTitle: "iPhone 영상 촬영", systemImageName: "video.fill"
        )
    }
}
