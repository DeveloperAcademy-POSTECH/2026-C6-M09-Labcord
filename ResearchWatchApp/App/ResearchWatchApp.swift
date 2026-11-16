import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS
import SwiftUI

@main
struct ResearchWatchApp: App {
    private enum Route: Hashable {
        case start(WatchExperimentSummary)
        case experiment(WatchExperimentSummary)

        var experimentID: UUID {
            switch self {
            case let .start(experiment), let .experiment(experiment):
                return experiment.id
            }
        }
    }

    @Dependency(\.watchConnectivitySession) var connectivity
    @Dependency(\.watchExperimentClient) var watchExperimentClient
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
                .onChange(of: path) { previous, current in
                    guard let experimentID = previous.last?.experimentID,
                          !current.contains(where: { $0.experimentID == experimentID })
                    else { return }
                    Task { await watchExperimentClient.cancelPhoneSession(experimentID) }
                }
            }
        }
        .backgroundTask(.watchConnectivity) { [connectivity] in
            await connectivity.waitForPendingUserInfo()
        }
    }
}
