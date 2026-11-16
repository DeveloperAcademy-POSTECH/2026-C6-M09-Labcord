import SwiftUI

import ComposableArchitecture
import LabcordWatchOS

@main
struct ResearchWatchApp: App {
    @Dependency(\.watchConnectivitySession) var connectivity

    var body: some Scene {
        WindowGroup {
            SelectExperimentView()
        }
        .backgroundTask(.watchConnectivity) { [connectivity] in
            await connectivity.waitForPendingUserInfo()
        }
    }
}
