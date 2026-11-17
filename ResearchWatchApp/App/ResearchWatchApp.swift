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
        case sort(UUID)

        var experimentID: UUID {
            switch self {
            case let .start(experiment), let .experiment(experiment):
                return experiment.id
            case let .sort(id):
                return id
            }
        }
    }

    @Dependency(\.watchConnectivitySession) var connectivity
    @Dependency(\.watchExperimentClient) var watchExperimentClient
    @State private var path: [Route] = []
    @State private var remoteScreen: WatchScreenSnapshot?
    @State private var pendingPhoneReentryID: UUID?
    @State private var phoneResultReadyIDs: Set<UUID> = []
    @State private var isVoiceRecordPresented = false
    @State private var suppressLeaveNotification = false

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
                            isVoiceRecordPresented: $isVoiceRecordPresented,
                            onPaused: {
                                suppressLeaveNotification = true
                                path = []
                            },
                            onCompleted: {
                                suppressLeaveNotification = true
                                path = [.sort(experiment.id)]
                            }
                        )
                    case let .sort(experimentID):
                        SortRecordView(
                            isPhoneResultReady: phoneResultReadyIDs.contains(experimentID),
                            onClose: {
                                phoneResultReadyIDs.remove(experimentID)
                                path = []
                            }
                        )
                    }
                }
                .onChange(of: path) { previous, current in
                    if case .some(.sort) = previous.last { return }
                    if case let .some(.experiment(experiment)) = previous.last {
                        let stillInExperiment: Bool
                        if case .some(.experiment) = current.last {
                            stillInExperiment = true
                        } else {
                            stillInExperiment = false
                        }
                        if !stillInExperiment {
                            let shouldNotify = !suppressLeaveNotification
                            suppressLeaveNotification = false
                            if shouldNotify {
                                Task {
                                    await watchExperimentClient.leavePhoneSession(experiment.id)
                                }
                                return
                            }
                        }
                    }
                    guard let experimentID = previous.last?.experimentID,
                          !current.contains(where: { $0.experimentID == experimentID })
                    else { return }
                    Task { await watchExperimentClient.cancelPhoneSession(experimentID) }
                }
            }
            .task { WatchVoiceRecordingService.shared.activate() }
            .task {
                connectivity.remoteIntentHandler = { request in
                    WatchRecordingShortcutCenter.shared.receive(request)
                }
                await connectivity.activate()
            }
            .task {
                for await screen in await watchExperimentClient.screens() {
                    if screen.destination == .result, let id = screen.experimentID {
                        phoneResultReadyIDs.insert(id)
                    }
                    let previousDestination = remoteScreen?.destination
                    if screen.destination != .experiment {
                        pendingPhoneReentryID = nil
                    } else if previousDestination != nil,
                              previousDestination != .experiment,
                              path.isEmpty {
                        pendingPhoneReentryID = screen.experimentID
                    }
                    remoteScreen = screen
                }
            }
            .task(id: ScreenSyncKey(
                revision: remoteScreen?.revision,
                isVoiceRecordPresented: isVoiceRecordPresented
            )) {
                guard !isVoiceRecordPresented, let screen = remoteScreen else { return }
                if case let .some(.experiment(experiment)) = path.last {
                    switch screen.destination {
                    case .home:
                        suppressLeaveNotification = true
                        path = []
                        return
                    case .result where screen.experimentID == experiment.id:
                        suppressLeaveNotification = true
                        path = [.sort(experiment.id)]
                        return
                    default:
                        break
                    }
                }
                guard screen.destination == .experiment,
                      let experimentID = screen.experimentID,
                      canOpenRemoteExperiment(experimentID),
                      screen.stage == .active || screen.stage == .timers
                          || screen.stage == .timerEditor else { return }
                while !Task.isCancelled, remoteScreen?.revision == screen.revision,
                      !isVoiceRecordPresented,
                      canOpenRemoteExperiment(experimentID) {
                    if let experiment = await experiment(for: experimentID),
                       !Task.isCancelled, remoteScreen?.revision == screen.revision,
                       !isVoiceRecordPresented,
                       canOpenRemoteExperiment(experimentID) {
                        pendingPhoneReentryID = nil
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

    private func canOpenRemoteExperiment(_ id: UUID) -> Bool {
        if case let .some(.start(selected)) = path.last { return selected.id == id }
        return path.isEmpty && pendingPhoneReentryID == id
    }

    private func experiment(for id: UUID) async -> WatchExperimentSummary? {
        if let listed = try? await watchExperimentClient.list().first(where: {
            $0.id == id && $0.status == .running
        }) {
            return listed
        }
        let response = try? await watchExperimentClient.send(
            WatchExperimentCommand(operation: .snapshot, experimentID: id)
        )
        guard let experiment = response?.snapshot?.experiment,
              experiment.status == .running else { return nil }
        return experiment
    }
}
