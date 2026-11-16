import ComposableArchitecture
import LabcordShared
import LabcordWatchOS
import SwiftUI

@main
struct ResearchWatchApp: App {
    private enum Route: Hashable {
        case start(WatchExperimentSummary)
        case experiment(WatchExperimentSummary)
    }

    @Dependency(\.watchConnectivitySession) var connectivity
    @State private var path: [Route] = []

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                SelectExperimentView { experiment in
                    path = [.start(experiment)]
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case let .start(experiment):
                        ExperimentStartView(experiment: experiment) {
                            path = [.experiment(experiment)]
                        }
                        .id(experiment.id)
                    case let .experiment(experiment):
                        ExperimentView(experiment: experiment)
                    }
                }
            }
        }
        .backgroundTask(.watchConnectivity) { [connectivity] in
            await connectivity.waitForPendingUserInfo()
        }
    }
}
