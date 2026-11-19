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

    @Environment(\.scenePhase) private var scenePhase
    @Dependency(\.watchConnectivitySession) var connectivity
    @Dependency(\.watchExperimentClient) var watchExperimentClient
    @State private var path: [Route] = []
    @State private var remoteScreen: WatchScreenSnapshot?
    @State private var pendingPhoneReentryID: UUID?
    @State private var dismissedStart: (id: UUID, until: Date)?
    @State private var voiceRecording: StoreOf<VoiceRecordFeature>?
    @State private var photoRecording: StoreOf<PhotoRecordFeature>?
    @State private var isRemoteNavigationBlocked = false
    @State private var needsRouteReconciliation = false
    @State private var suppressLeaveNotification = false

    @State private var debugRootRevision = 0

    private var isRecordPresented: Bool { voiceRecording != nil || photoRecording != nil }

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
                    pendingPhoneReentryID = nil
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
                            voiceRecording: $voiceRecording,
                            photoRecording: $photoRecording,
                            phoneScreen: $remoteScreen,
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
                        .navigationBarBackButtonHidden(true)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    leaveExperimentOnWatch(experiment)
                                } label: {
                                    Image(systemName: "chevron.left")
                                }
                                .accessibilityLabel("실험 목록으로 돌아가기")
                            }
                        }
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
                        WatchRecordingShortcutCenter.shared.enterExperiment(entered.id)
                        Task { await watchExperimentClient.enterPhoneSession(entered.id) }
                    }
                    if case let .some(.start(experiment)) = previous.last, current.isEmpty {
                        let until = Date.now.addingTimeInterval(WatchSessionOpenRequest.lifetime)
                        dismissedStart = (experiment.id, until)
                        pendingPhoneReentryID = nil
                    }
                    if case .some(.sort) = previous.last { return }
                    if case let .some(.experiment(experiment)) = previous.last {
                        if case let .some(.experiment(next)) = current.last {
                            if next.id != experiment.id {
                                photoRecording = nil
                                WatchRecordingShortcutCenter.shared.leaveExperiment(experiment.id)
                            }
                        } else {
                            photoRecording = nil
                            WatchRecordingShortcutCenter.shared.leaveExperiment(experiment.id)
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
            .onChange(of: photoRecording) { previous, _ in
                previous?.send(.presentationEnded)
            }
            .onChange(of: WatchRecordingShortcutCenter.shared.restorationID, initial: true) {
                restoreGestureExperiment()
            }
            .onChange(of: voiceRecording) { previous, _ in
                previous?.send(.disappeared)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active,
                      case let .experiment(experiment)? = path.last else { return }
                if let phase = voiceRecording?.phase,
                   [.awaitingTransfer, .transcribing, .saving].contains(phase) {
                    WatchVoiceRecordingService.shared.retryDelivery()
                }
                Task { await watchExperimentClient.enterPhoneSession(experiment.id) }
            }
            .modifier(WatchDebugMenuModifier())
            .environment(\.watchDebugReset, WatchDebugResetAction(call: resetToStart))
            .task { WatchVoiceRecordingService.shared.activate() }
            .task {
                connectivity.remoteIntentHandler = { request in
                    await WatchRecordingShortcutCenter.shared.receive(request)
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
                    } else if path.isEmpty, previous?.destination != .experiment
                        || previous?.experimentID != screen.experimentID
                        || previous?.epoch != screen.epoch {
                        pendingPhoneReentryID = screen.experimentID
                    }
                    remoteScreen = screen
                }
            }
            .task(id: ScreenSyncKey(
                epoch: remoteScreen?.epoch, revision: remoteScreen?.revision,
                isNavigationBlocked: isRecordPresented || isRemoteNavigationBlocked
            )) {
                guard !isRecordPresented, !isRemoteNavigationBlocked,
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
                      !isRecordPresented, !isRemoteNavigationBlocked,
                      canOpenRemoteExperiment(experimentID) {
                    if let experiment = await experiment(for: screen, id: experimentID),
                       !Task.isCancelled, isCurrent(screen),
                       !isRecordPresented, !isRemoteNavigationBlocked,
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
}

private extension ResearchWatchApp {
    func restoreGestureExperiment() {
        guard path.isEmpty, !isRecordPresented, !isRemoteNavigationBlocked,
              let (experiment, screen) = WatchRecordingShortcutCenter.shared.currentRestoration(),
              !ignoresRemoteStart(experiment.id) else { return }
        remoteScreen = screen
        pendingPhoneReentryID = nil
        path = [.experiment(experiment)]
    }

    func leaveExperimentOnWatch(_ experiment: WatchExperimentSummary) {
        guard path.last == .experiment(experiment) else { return }
        dismissedStart = (
            experiment.id, Date.now.addingTimeInterval(WatchSessionOpenRequest.lifetime)
        )
        pendingPhoneReentryID = nil
        path.removeLast()
    }

    func resetToStart() {
        voiceRecording = nil
        photoRecording = nil
        pendingPhoneReentryID = nil
        dismissedStart = nil
        needsRouteReconciliation = false
        isRemoteNavigationBlocked = false
        if case .some(.experiment) = path.last { suppressLeaveNotification = true }
        path.removeAll()
        debugRootRevision += 1
    }

    func canOpenRemoteExperiment(_ id: UUID) -> Bool {
        path.isEmpty && pendingPhoneReentryID == id && !ignoresRemoteStart(id)
    }

    func ignoresRemoteStart(_ id: UUID?) -> Bool {
        guard let dismissedStart else { return false }
        return dismissedStart.id == id && .now < dismissedStart.until
    }

    func isCurrent(_ screen: WatchScreenSnapshot) -> Bool {
        remoteScreen?.epoch == screen.epoch && remoteScreen?.revision == screen.revision
    }

    func experiment(for screen: WatchScreenSnapshot, id: UUID) async
        -> WatchExperimentSummary? {
        // 첫 화면은 이전 실행의 application context일 수 있으므로 iPhone의 현재 화면을 확인합니다.
        let list = try? await watchExperimentClient.send(WatchExperimentCommand(operation: .list))
        var current = list?.screen
        if current == nil {
            current = try? await watchExperimentClient.send(
                WatchExperimentCommand(operation: .screen)
            ).screen
        }
        guard let current, current.epoch == screen.epoch, current.revision == screen.revision,
              current.hasSameContent(as: screen), !Task.isCancelled else { return nil }
        if let experiments = list?.experiments {
            return experiments.first { $0.id == id && $0.status == .running }
        }
        let response = try? await watchExperimentClient.send(
            WatchExperimentCommand(operation: .snapshot, experimentID: id)
        )
        guard let experiment = response?.snapshot?.experiment,
              experiment.status == .running else { return nil }
        return experiment
    }
}
