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
        case connection
        case gestures
    }

    enum RequestPhase: Equatable {
        case delivering
        case processing
        case uncertain
    }

    struct PendingRequest: Equatable {
        let command: WatchExperimentCommand
        var responseID: UUID
        var phase: RequestPhase = .delivering
    }

    @ObservableState
    struct State: Equatable {
        var screen: Screen = .selection
        var experiments: [WatchExperimentSummary] = []
        var selectedID: UUID?
        var snapshots: [UUID: WatchExperimentSnapshot] = [:]
        var pending: PendingRequest?
        var startToken: UUID?
        var isReachable = false
        var isVisible = false
        var streamID: UUID?
        var message: String?
        var permissionDenied = false
        var currentTime = Date.now

        var snapshot: WatchExperimentSnapshot? {
            selectedID.flatMap { snapshots[$0] }
        }

        var selectedTitle: String {
            snapshot?.experiment.title
                ?? experiments.first { $0.id == selectedID }?.title ?? "실험 선택"
        }

        var canOperate: Bool {
            pending == nil && isReachable && snapshot != nil
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
        case connectionTapped
        case gesturesTapped
        case closeTapped
        case checkRequest
        case response(UUID, WatchExperimentResponse)
        case requestFailed(UUID, WatchExperimentError)
        case deliveryExpired(UUID)
        case pollRequest(UUID)
        case tick(Date)
    }

    nonisolated enum CancelID: Hashable, Sendable {
        case stream
        case connection
        case request
        case delivery
        case poll
        case countdown
        case permission
    }

    @Dependency(\.watchExperimentClient) var client
    @Dependency(\.watchMicrophonePermission) var microphonePermission
    @Dependency(\.continuousClock) var clock
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                return activate(state: &state)
            case .inactive:
                state.isVisible = false
                state.streamID = nil
                if case .countdown = state.screen {
                    state.screen = .experiment
                    state.startToken = nil
                }
                if state.pending != nil { state.pending?.phase = .uncertain }
                return .merge(CancelID.all.map { .cancel(id: $0) })
            case .refresh:
                guard state.isVisible else { return .none }
                if state.pending != nil { return checkStatus(state: &state) }
                let operation: WatchExperimentCommand.Operation =
                    state.selectedID == nil ? .list : .snapshot
                return request(operation, state: &state)
            case let .selected(id):
                guard state.pending == nil,
                      state.experiments.contains(where: { $0.id == id }) else {
                    return .none
                }
                state.selectedID = id
                state.startToken = nil
                state.screen = .experiment
                state.message = nil
                return request(.snapshot, state: &state)
            case .backTapped:
                guard state.pending == nil else { return .none }
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
            case .permissionRequested:
                guard state.screen == .permission, let id = state.selectedID else { return .none }
                return .run { [microphonePermission] send in
                    let granted = await microphonePermission.request()
                    guard !Task.isCancelled else { return }
                    await send(.permissionResult(id, granted))
                }
                .cancellable(id: CancelID.permission, cancelInFlight: true)
            case let .permissionResult(id, granted):
                guard state.isVisible, state.selectedID == id, state.screen == .permission else {
                    return .none
                }
                state.permissionDenied = !granted
                guard granted else { return .none }
                state.screen = .experiment
                return request(.prepareStart, state: &state)
            case let .countdownTick(token):
                guard state.startToken == token, case let .countdown(seconds) = state.screen else {
                    return .none
                }
                guard seconds > 1 else {
                    state.screen = .experiment
                    return request(.start, token: token, state: &state)
                }
                state.screen = .countdown(seconds - 1)
                return countdown(token: token)
            case .cancelCountdown:
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
                guard state.canOperate else { return .none }
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
                return request(operation, state: &state)
            case .resumeTapped:
                guard state.snapshot?.experiment.status == .paused else { return .none }
                return request(.resume, state: &state)
            case .connectionTapped:
                state.screen = .connection
                return .none
            case .gesturesTapped:
                state.screen = .gestures
                return .none
            case .closeTapped:
                state.startToken = nil
                state.screen = state.selectedID == nil ? .selection : .experiment
                state.message = nil
                return .merge(
                    .cancel(id: CancelID.permission), .cancel(id: CancelID.countdown)
                )
            case .checkRequest:
                return checkStatus(state: &state)
            case .response, .requestFailed, .deliveryExpired, .pollRequest,
                 .snapshotReceived, .streamEnded, .connectionChanged, .tick:
                return reduceResponse(state: &state, action: action)
            }
        }
    }

    func countdown(token: UUID) -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: .seconds(1))
            await send(.countdownTick(token))
        }
        .cancellable(id: CancelID.countdown, cancelInFlight: true)
    }
}

extension WatchExperimentFeature.CancelID {
    static let all: [Self] = [
        .stream, .connection, .request, .delivery, .poll, .countdown, .permission
    ]
}
