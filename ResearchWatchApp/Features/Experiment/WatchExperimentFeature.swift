import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

@Reducer
struct WatchExperimentFeature {
    enum Screen: Equatable {
        case selection
        case experiment
        case permission
        case countdown(Int)
        case confirmPause
        case confirmComplete
        case confirmResume
        case recordCleanup
        case connection
        case gestures
        case timers
        case timerEditor
        case phoneRegistration
    }

    @ObservableState
    struct State: Equatable {
        var screen: Screen = .selection
        var experiments: [WatchExperimentSummary] = []
        var lastReadRequestID: UUID?
        var practice = WatchGesturePractice()
        var selectedID: UUID?
        var snapshots: [UUID: WatchExperimentSnapshot] = [:]
        var deferredPhoneSession: WatchExperimentSnapshot?
        var phoneScreen: WatchScreenSnapshot?
        var deferredScreen: WatchScreenSnapshot?
        var queuedNavigation: WatchScreenSnapshot?
        var queuedNavigationRequestID: UUID?
        var queuedNavigationDiscardsTimerDraft = false
        var localCountdownEndsAt: Date?
        var screenRecoveryNeeded = false
        var pending: PendingRequest?
        var hasRestoredPending = false
        var pendingRecoveryFailed = false
        var canRetryPendingCancellation = false
        var startToken: UUID?
        var countdownID: UUID?
        var authorization: Authorization?
        var isReachable = false
        var connectionStatus: WatchConnectionStatus = .activating
        var isVisible = false
        var streamID: UUID?
        var recordObservationID: UUID?
        var recordObservationReady = false
        var message: String?
        var permissionDenied = false
        var isRequestingPermission = false
        var permissionRequestID: UUID?
        var cleanupRequestID: UUID?
        var currentTime = Date.now
        var recording = WatchRecordFeature.State()
        var timerHours = 0
        var timerMinutes = 1
        var timerSeconds = 0
        var isPreparingInterruption = false
        var interruptionAttemptID: UUID?
        var interruptionNeedsConfirmation = false

    }

    enum Action: Equatable {
        case appeared
        case inactive
        case refresh
        case connectionChanged(UUID, Bool)
        case connectionStatusChanged(UUID, WatchConnectionStatus)
        case retryConnection
        case streamEnded(UUID)
        case snapshotReceived(UUID, WatchExperimentSnapshot)
        case screenReceived(UUID, WatchScreenSnapshot)
        case screenStreamEnded(UUID)
        case selected(UUID)
        case backTapped
        case startTapped
        case permissionRequested
        case permissionResult(UUID, UUID, Bool)
        case voicePermissionResult(UUID, UUID, Bool)
        case remoteVoiceRequested(UUID, Date)
        case remoteVoicePermissionResult(UUID, UUID, Date, Bool)
        case countdownTick(UUID)
        case cancelCountdown
        case pauseTapped
        case completeTapped
        case confirmed
        case resumeTapped
        case resumeConfirmed
        case connectionTapped
        case gesturesTapped
        case closeTapped
        case checkRequest
        case retryPendingCancellation
        case response(UUID, WatchExperimentResponse)
        case requestFailed(UUID, WatchExperimentError)
        case deliveryExpired(UUID)
        case pollRequest(UUID)
        case tick(Date)
        case timersTapped
        case timerEditorTapped
        case timerHoursChanged(Int)
        case timerMinutesChanged(Int)
        case timerSecondsChanged(Int)
        case timerStarted(Int)
        case customTimerStarted
        case timerPaused(UUID)
        case timerResumed(UUID)
        case timerDeleted(UUID)
        case recording(WatchRecordFeature.Action)
        case recordTapped(WatchRecordPresentation.Kind)
        case practiceRecord(WatchRecordPresentation.Kind)
        case recordUpdate(UUID, WatchRecordPresentation)
        case recordReconnect
        case recordStreamReady(UUID, UUID)
        case recordStreamEnded(UUID, UUID)
        case recordRecoveryFinished(UUID?, Bool)
        case interruptionPrepared(UUID, UUID, WatchExperimentCommand.Operation)
        case interruptionFailed(UUID, UUID), cancelInterruptionPreparation
    }

    nonisolated enum CancelID: Hashable, Sendable {
        case stream
        case connection
        case request
        case delivery
        case poll
        case countdown
        case permission
        case recordStream
        case screenStream
        case interruptionTimeout
        case interruptionWork
    }

    var recordingBridge: WatchRecordingUIBridge?
    var pendingJournal: WatchPendingRequestJournal = .live

    @Dependency(\.watchExperimentClient) var client
    @Dependency(\.watchMicrophonePermission) var microphonePermission
    @Dependency(\.continuousClock) var clock
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now

    var body: some Reducer<State, Action> {
        Scope(state: \.recording, action: \.recording) { WatchRecordFeature() }
        Reduce { state, action in
            switch action {
            case .appeared:
                return activate(state: &state)
            case .inactive:
                return deactivate(state: &state)
            case .refresh:
                guard state.isVisible, restorePending(state: &state) else { return .none }
                if state.pending != nil { return checkStatus(state: &state) }
                let operation: WatchExperimentCommand.Operation =
                    state.selectedID == nil ? .list : .snapshot
                return request(operation, state: &state)
            case let .selected(id):
                guard state.pending == nil,
                      !state.recording.hasUnsettledRecords(in: state.selectedID),
                      !state.isPreparingInterruption,
                      state.experiments.contains(where: { $0.id == id }) else {
                    return .none
                }
                return selectExperiment(id, state: &state)
            case .backTapped:
                guard state.pending == nil,
                      !state.recording.hasUnsettledRecords(in: state.selectedID),
                      !state.isPreparingInterruption else { return .none }
                return navigate(.init(destination: .home), state: &state)
            case .startTapped:
                guard state.canOperate, state.snapshot?.experiment.status == .ready else {
                    return .none
                }
                return navigateToStage(.permission, state: &state)
            case .permissionRequested, .permissionResult:
                return reduceStart(state: &state, action: action)
            case let .countdownTick(token):
                guard state.isVisible, state.streamID != nil, state.countdownID == token,
                      case let .countdown(seconds) = state.screen else {
                    return .none
                }
                guard seconds > 1 else {
                    state.countdownID = nil
                    state.screen = .countdown(0)
                    guard state.localCountdownEndsAt != nil else { return .none }
                    state.localCountdownEndsAt = nil
                    state.screen = .experiment
                    return request(.start, state: &state)
                }
                state.screen = .countdown(seconds - 1)
                return countdown(token: token)
            case .cancelCountdown:
                state.countdownID = nil
                state.startToken = nil
                state.localCountdownEndsAt = nil
                return .merge(.cancel(id: CancelID.countdown), navigateToExperiment(state: &state))
            case .pauseTapped:
                guard state.canOperate, state.snapshot?.experiment.status == .running else {
                    return .none
                }
                return navigateToStage(.pauseConfirmation, state: &state)
            case .completeTapped:
                guard state.canOperate, state.snapshot?.experiment.status != .ready,
                      state.snapshot?.experiment.status != .completed else { return .none }
                return navigateToStage(.completionConfirmation, state: &state)
            case .confirmed:
                let operation: WatchExperimentCommand.Operation
                switch state.screen {
                case .confirmPause: operation = .pause
                case .confirmComplete: operation = .complete
                default: return .none
                }
                state.interruptionNeedsConfirmation = false
                state.screen = .experiment
                return prepareInterruption(operation, state: &state)
            case .resumeTapped:
                guard state.canOperate, state.canResume else { return .none }
                return navigateToStage(.resumeConfirmation, state: &state)
            case .resumeConfirmed:
                guard state.screen == .confirmResume, state.canOperate, state.canResume else {
                    return .none
                }
                state.screen = .experiment
                return request(.resume, state: &state)
            case .connectionTapped:
                state.screen = .connection
                return .none
            case .gesturesTapped:
                return navigateToStage(.gestures, state: &state)
            case .closeTapped:
                return close(state: &state)
            case .checkRequest:
                return checkStatus(state: &state)
            case .retryPendingCancellation:
                return retryPendingCancellation(state: &state)
            default:
                return reduceTools(state: &state, action: action)
            }
        }
        Reduce { state, _ in
            resumeScreenSynchronization(state: &state)
        }
    }
}

extension WatchExperimentFeature.CancelID {
    static let all: [Self] = [
        .stream, .connection, .request, .delivery, .poll, .countdown, .permission, .recordStream,
        .interruptionTimeout, .interruptionWork, .screenStream
    ]
}
