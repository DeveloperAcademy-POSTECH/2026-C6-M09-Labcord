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
    }

    @Dependency(\.watchConnectivitySession) var connectivity
    @Dependency(\.watchExperimentClient) var watchExperimentClient
    @State private var path: [Route] = []
    @State private var remoteScreen: WatchScreenSnapshot?
    @State private var pendingPhoneReentryID: UUID?
    @State private var dismissedStart: (id: UUID, until: Date)?
    @State private var isVoiceRecordPresented = false
    @State private var isRemoteNavigationBlocked = false
    @State private var needsRouteReconciliation = false
    @State private var suppressLeaveNotification = false

    @State private var debugRootRevision = 0

    private struct ScreenSyncKey: Hashable {
        let epoch: WatchStateEpoch?
        let revision: UInt64?
        let isNavigationBlocked: Bool
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                SelectExperimentView { experiment in
                    dismissedStart = nil
                    path = [.start(experiment)]
                }
                .id(debugRootRevision)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case let .start(experiment):
                        ExperimentStartView(experiment: experiment) {
                            guard path.last == .start(experiment) else { return }
                            path = [.experiment(experiment)]
                        }
                        .id(experiment.id)
                    case let .experiment(experiment):
                        ExperimentView(
                            experiment: experiment,
                            isVoiceRecordPresented: $isVoiceRecordPresented,
                            onNavigationBlockedChanged: { isRemoteNavigationBlocked = $0 },
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
                            experimentID: experimentID,
                            isPhoneResultReady: remoteScreen?.destination == .result
                                && remoteScreen?.experimentID == experimentID,
                            sendCommand: watchExperimentClient.send
                        ) {
                            path = []
                        }
                    }
                }
                .onChange(of: path) { previous, current in
                    if case let .some(.experiment(entered)) = current.last,
                       previous.last != current.last {
                        Task { await watchExperimentClient.enterPhoneSession(entered.id) }
                    }
                    if case let .some(.start(experiment)) = previous.last, current.isEmpty {
                        let until = Date.now.addingTimeInterval(WatchSessionOpenRequest.lifetime)
                        dismissedStart = (experiment.id, until)
                        pendingPhoneReentryID = nil
                    }
                    if case .some(.sort) = previous.last { return }
                    if case let .some(.experiment(experiment)) = previous.last {
                        let stillInExperiment: Bool
                        if case .some(.experiment) = current.last {
                            stillInExperiment = true
                        } else {
                            stillInExperiment = false
                        }
                        if !stillInExperiment {
                            isRemoteNavigationBlocked = false
                            let shouldNotify = !suppressLeaveNotification
                            suppressLeaveNotification = false
                            if shouldNotify {
                                Task {
                                    await watchExperimentClient.leavePhoneSession(experiment.id)
                                }
                            }
                        }
                    }
                }
            }
            .modifier(WatchDebugMenuModifier())
            .environment(\.watchDebugReset, WatchDebugResetAction(call: resetToStart))
            .task { WatchVoiceRecordingService.shared.activate() }
            .task {
                connectivity.remoteIntentHandler = { request in
                    WatchRecordingShortcutCenter.shared.receive(request)
                }
                await connectivity.activate()
            }
            .task {
                for await screen in await watchExperimentClient.screens() {
                    let previous = remoteScreen
                    if let previous, previous.epoch != screen.epoch {
                        dismissedStart = nil
                        needsRouteReconciliation = true
                    }
                    if previous?.destination == .experiment,
                       previous?.experimentID == dismissedStart?.id,
                       screen.destination != .experiment
                        || screen.experimentID != dismissedStart?.id {
                        dismissedStart = nil
                    }
                    if screen.destination != .experiment
                        || ignoresRemoteStart(screen.experimentID) {
                        pendingPhoneReentryID = nil
                    } else if let previous,
                              previous.destination != .experiment
                                || previous.experimentID != screen.experimentID,
                              path.isEmpty {
                        pendingPhoneReentryID = screen.experimentID
                    }
                    remoteScreen = screen
                }
            }
            .task(id: ScreenSyncKey(
                epoch: remoteScreen?.epoch, revision: remoteScreen?.revision,
                isNavigationBlocked: isVoiceRecordPresented || isRemoteNavigationBlocked
            )) {
                guard !isVoiceRecordPresented, !isRemoteNavigationBlocked,
                      let screen = remoteScreen else { return }
                let reconcileRoute = needsRouteReconciliation
                needsRouteReconciliation = false
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
                        if reconcileRoute, screen.experimentID != experiment.id {
                            suppressLeaveNotification = true
                            path = []
                            if screen.destination == .experiment {
                                pendingPhoneReentryID = screen.experimentID
                            }
                        }
                    }
                }
                guard screen.destination == .experiment,
                      let experimentID = screen.experimentID,
                      canOpenRemoteExperiment(experimentID),
                      screen.stage == .active || screen.stage == .timers
                          || screen.stage == .timerEditor else { return }
                while !Task.isCancelled, isCurrent(screen),
                      !isVoiceRecordPresented, !isRemoteNavigationBlocked,
                      canOpenRemoteExperiment(experimentID) {
                    if let experiment = await experiment(for: experimentID),
                       !Task.isCancelled, isCurrent(screen),
                       !isVoiceRecordPresented, !isRemoteNavigationBlocked,
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

    private func resetToStart() {
        isVoiceRecordPresented = false
        pendingPhoneReentryID = nil
        dismissedStart = nil
        needsRouteReconciliation = false
        isRemoteNavigationBlocked = false
        if case .some(.experiment) = path.last { suppressLeaveNotification = true }
        path.removeAll()
        debugRootRevision += 1
    }

    private func canOpenRemoteExperiment(_ id: UUID) -> Bool {
        path.isEmpty && pendingPhoneReentryID == id && !ignoresRemoteStart(id)
    }

    private func ignoresRemoteStart(_ id: UUID?) -> Bool {
        guard let dismissedStart else { return false }
        return dismissedStart.id == id && .now < dismissedStart.until
    }

    private func isCurrent(_ screen: WatchScreenSnapshot) -> Bool {
        remoteScreen?.epoch == screen.epoch && remoteScreen?.revision == screen.revision
    }

    private func experiment(for id: UUID) async -> WatchExperimentSummary? {
        if let listed = try? await watchExperimentClient.list().experiments.first(where: {
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
