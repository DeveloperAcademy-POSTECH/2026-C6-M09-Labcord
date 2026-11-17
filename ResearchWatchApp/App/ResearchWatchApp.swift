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
    @State private var remoteScreen: WatchScreenSnapshot?
    @State private var isVoiceRecordPresented = false

    private struct ScreenSyncKey: Hashable {
        let revision: UInt64?
        let isVoiceRecordPresented: Bool
    }

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
                        ExperimentView(
                            experiment: experiment,
                            isVoiceRecordPresented: $isVoiceRecordPresented
                        )
                    }
                }
                .onChange(of: path) { previous, current in
                    guard let experimentID = previous.last?.experimentID,
                          !current.contains(where: { $0.experimentID == experimentID })
                    else { return }
                    Task { await watchExperimentClient.cancelPhoneSession(experimentID) }
                }
            }
            .task { WatchVoiceRecordingService.shared.activate() }
            .task {
                for await screen in await watchExperimentClient.screens() {
                    remoteScreen = screen
                }
            }
            .task(id: ScreenSyncKey(
                revision: remoteScreen?.revision,
                isVoiceRecordPresented: isVoiceRecordPresented
            )) {
                guard !isVoiceRecordPresented,
                      let screen = remoteScreen, screen.destination == .experiment,
                      let experimentID = screen.experimentID,
                      path.last?.experimentID != experimentID else { return }
                while !Task.isCancelled, remoteScreen?.revision == screen.revision,
                      !isVoiceRecordPresented, path.last?.experimentID != experimentID {
                    if let experiment = await experiment(for: experimentID),
                       !Task.isCancelled, remoteScreen?.revision == screen.revision,
                       !isVoiceRecordPresented {
                        path = [.experiment(experiment)]
                        return
                    }
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
        .backgroundTask(.watchConnectivity) { [connectivity] in
            await connectivity.waitForPendingUserInfo()
        }
    }

    private func experiment(for id: UUID) async -> WatchExperimentSummary? {
        if let listed = try? await watchExperimentClient.list().first(where: { $0.id == id }) {
            return listed
        }
        let response = try? await watchExperimentClient.send(
            WatchExperimentCommand(operation: .snapshot, experimentID: id)
        )
        guard let experiment = response?.snapshot?.experiment,
              experiment.status != .completed else { return nil }
        return experiment
    }
}
