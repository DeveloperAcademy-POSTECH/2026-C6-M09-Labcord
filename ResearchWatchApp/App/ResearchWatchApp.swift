import SwiftUI

import ComposableArchitecture
import LabcordShared
import LabcordWatchOS

@main
struct ResearchWatchApp: App {
    @Dependency(\.watchConnectivitySession) var connectivity
    @Dependency(\.microphonePermissionClient) var microphonePermission

    init() {
        connectivity.remoteIntentHandler = { request in
            await WatchRemoteIntentReceiver.shared.receive(request)
        }
        #if DEBUG && targetEnvironment(simulator)
        connectivity.recordingTestTriggerHandler = { command in
            let kind: WatchRecordPresentation.Kind
            switch command {
            case "audio": kind = .voice
            case "photo": kind = .photo
            case "video": kind = .video
            default: return false
            }
            do {
                WatchDemoPressState.shared.show(kind)
                try await Task.sleep(for: .milliseconds(400))
                _ = try await WatchIntentRuntime.shared.perform(kind)
                return true
            } catch {
                return false
            }
        }
        #endif
        WatchRecordingService.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: WatchIntentRuntime.shared.store)
                .task { _ = await microphonePermission.requestAccess() }
        }
        .backgroundTask(.watchConnectivity) { [connectivity] in
            await connectivity.waitForPendingUserInfo()
        }
    }
}
