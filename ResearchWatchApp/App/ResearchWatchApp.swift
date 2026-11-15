import SwiftUI

import ComposableArchitecture
import LabcordWatchOS

@main
struct ResearchWatchApp: App {
    @Dependency(\.watchConnectivitySession) var connectivity

    init() {
        connectivity.remoteIntentHandler = { request in
            await WatchRemoteIntentReceiver.shared.receive(request)
        }
        WatchRecordingService.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: WatchIntentRuntime.shared.store)
        }
        .backgroundTask(.watchConnectivity) { [connectivity] in
            await connectivity.waitForPendingUserInfo()
        }
    }
}
