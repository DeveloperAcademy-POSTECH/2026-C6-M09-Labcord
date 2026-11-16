import ComposableArchitecture
import LabcordShared
import LabcordWatchOS
import SwiftUI

@main
struct ResearchWatchApp: App {
    private enum Route: Hashable {
        case start
        case experiment
    }

    @Dependency(\.watchConnectivitySession) var connectivity
    @State private var path: [Route] = []
    @State private var selectedExperiment: WatchExperimentSummary?

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                SelectExperimentView { experiment in
                    selectedExperiment = experiment
                    path = [.start]
                }
                .navigationDestination(for: Route.self) { route in
                    if let selectedExperiment {
                        switch route {
                        case .start:
                            ExperimentStartView(experiment: selectedExperiment) {
                                path = [.experiment]
                            }
                        case .experiment:
                            ExperimentView(experiment: selectedExperiment)
                        }
                    }
                }
            }
        }
        .backgroundTask(.watchConnectivity) { [connectivity] in
            await connectivity.waitForPendingUserInfo()
        }
    }
}
