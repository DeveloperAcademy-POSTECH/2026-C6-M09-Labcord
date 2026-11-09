import SwiftUI

import ComposableArchitecture
import LabcordWatchOS

@main
struct ResearchWatchApp: App {
    @Dependency(\.watchBatteryClient) private var batteryClient
    @Dependency(\.watchDeviceNameClient) private var deviceNameClient
    @Dependency(\.watchConnectivitySession) var connectivity

    init() {
        connectivity.remoteIntentHandler = { request in
            await WatchRemoteIntentReceiver.shared.receive(request)
        }
        WatchRecordingService.shared.activate()
        batteryClient.start()
        deviceNameClient.start()
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
