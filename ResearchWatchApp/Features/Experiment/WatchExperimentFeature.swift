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
    }

    @ObservableState
    struct State: Equatable {
        var screen: Screen = .selection
        var experiments: [WatchExperimentSummary] = []
        var lastReadRequestID: UUID?
        var practice = WatchGesturePractice()
        var selectedID: UUID?
        var snapshots: [UUID: WatchExperimentSnapshot] = [:]
        var pending: PendingRequest?
        var hasRestoredPending = false
        var pendingRecoveryFailed = false
        var canRetryPendingCancellation = false
        var startToken: UUID?
        var countdownID: UUID?
        var authorization: Authorization?
        var isReachable = false
        var isVisible = false
        var streamID: UUID?
        var message: String?
        var permissionDenied = false
        var isRequestingPermission = false
        var cleanupRequestID: UUID?
        var currentTime = Date.now
        var recording = WatchRecordFeature.State()
        var timerHours = 0
        var timerMinutes = 1
        var timerSeconds = 0
        var isPreparingInterruption = false

        var snapshot: WatchExperimentSnapshot? {
            selectedID.flatMap { snapshots[$0] }
        }

        var selectedTitle: String {
            snapshot?.experiment.title
                ?? experiments.first { $0.id == selectedID }?.title ?? "실험 선택"
        }

        var canReviewCompletedExperiment: Bool {
            cleanupRequestID != nil && recording.isIntegrated
                && snapshot?.experiment.status == .completed && pending == nil
                && !recording.hasUnsettledRecords(in: selectedID)
        }

        var canOperate: Bool {
            isVisible && streamID != nil && pending == nil && isReachable
                && snapshot != nil && !isPreparingInterruption && !pendingRecoveryFailed
        }
    }

    enum Action: Equatable {
        case appeared
        case inactive
        case refresh
        case connectionChanged(UUID, Bool)
        case streamEnded(UUID)
        case snapshotReceived(UUID, WatchExperimentSnapshot)
        case selected(UUID)
        case backTapped
        case startTapped
        case permissionRequested
        case permissionResult(UUID, Bool)
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
        case recordStreamEnded(UUID)
        case interruptionPrepared(UUID, WatchExperimentCommand.Operation)
        case interruptionFailed(UUID)
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
                state.isVisible = false
                state.isRequestingPermission = false
                state.cleanupRequestID = nil
                state.streamID = nil
                state.authorization = nil
                state.countdownID = nil
                if case .countdown = state.screen {
                    state.screen = .experiment
                    state.startToken = nil
                }
                if let pending = state.pending,
                   WatchRequestPolicy.canAbandon(pending.command.operation) {
                    state.pending = nil
                } else if state.pending != nil {
                    state.pending?.phase = .uncertain
                }
                return .merge(
                    .merge(CancelID.all.map { .cancel(id: $0) }),
                    .send(.recording(.interrupted))
                )
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
                state.selectedID = id
                state.startToken = nil
                state.screen = .experiment
                state.message = nil
                return request(.snapshot, state: &state)
            case .backTapped:
                guard state.pending == nil,
                      !state.recording.hasUnsettledRecords(in: state.selectedID),
                      !state.isPreparingInterruption else { return .none }
                state.screen = .selection
                state.selectedID = nil
                state.startToken = nil
                return request(.list, state: &state)
            case .startTapped:
                guard state.canOperate, state.snapshot?.experiment.status == .ready else {
                    return .none
                }
                state.screen = .permission
                return .none
            case .permissionRequested, .permissionResult:
                return reduceStart(state: &state, action: action)
            case let .countdownTick(token):
                guard state.isVisible, state.streamID != nil, state.countdownID == token,
                      case let .countdown(seconds) = state.screen else {
                    return .none
                }
                guard seconds > 1 else {
                    state.screen = .experiment
                    state.countdownID = nil
                    return request(.start, state: &state)
                }
                state.screen = .countdown(seconds - 1)
                return countdown(token: token)
            case .cancelCountdown:
                state.countdownID = nil
                state.startToken = nil
                state.screen = .experiment
                return .cancel(id: CancelID.countdown)
            case .pauseTapped:
                guard state.canOperate, state.snapshot?.experiment.status == .running else {
                    return .none
                }
                state.screen = .confirmPause
                return .none
            case .completeTapped:
                guard state.canOperate, state.snapshot?.experiment.status != .ready,
                      state.snapshot?.experiment.status != .completed else { return .none }
                state.screen = .confirmComplete
                return .none
            case .confirmed:
                let operation: WatchExperimentCommand.Operation
                switch state.screen {
                case .confirmPause: operation = .pause
                case .confirmComplete: operation = .complete
                default: return .none
                }
                state.screen = .experiment
                return prepareInterruption(operation, state: &state)
            case .resumeTapped:
                guard state.canOperate,
                      state.snapshot?.experiment.status == .paused else { return .none }
                state.screen = .confirmResume
                return .none
            case .resumeConfirmed:
                guard state.screen == .confirmResume, state.canOperate,
                      state.snapshot?.experiment.status == .paused else { return .none }
                state.screen = .experiment
                return request(.resume, state: &state)
            case .connectionTapped:
                state.screen = .connection
                return .none
            case .gesturesTapped:
                state.screen = .gestures
                return .none
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
    }
}

extension WatchExperimentFeature.CancelID {
    static let all: [Self] = [
        .stream, .connection, .request, .delivery, .poll, .countdown, .permission, .recordStream
    ]
}
