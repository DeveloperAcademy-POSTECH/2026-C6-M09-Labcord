import AppIntents

/// 앱을 전면으로 연 뒤 공통 화면 처리 경로에 전달한다. 백그라운드 녹음 시작 Intent가 아니다.
struct ToggleWatchVoiceRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "실험 음성 녹음 시작 또는 중지"
    static let description = IntentDescription("현재 실험의 음성 녹음을 시작하거나 중지합니다.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await WatchIntentRuntime.shared.perform(.voice)
        return .result(dialog: "\(message)")
    }
}

struct TakeWatchPhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "실험 사진 촬영"
    static let description = IntentDescription("현재 실험의 사진 촬영을 요청합니다.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await WatchIntentRuntime.shared.perform(.photo)
        return .result(dialog: "\(message)")
    }
}

struct ToggleWatchVideoRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "실험 영상 녹화 시작 또는 중지"
    static let description = IntentDescription("현재 실험의 영상 녹화를 시작하거나 중지합니다.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await WatchIntentRuntime.shared.perform(.video)
        return .result(dialog: "\(message)")
    }
}
