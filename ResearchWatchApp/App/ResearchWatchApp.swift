import SwiftUI

import ComposableArchitecture
import LabcordWatchOS

@main
struct ResearchWatchApp: App {
    @Dependency(\.watchConnectivitySession) var connectivity

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SelectExperimentView()
            }
        }
        .backgroundTask(.watchConnectivity) { [connectivity] in
            await connectivity.waitForPendingUserInfo()
        }
    }
}
