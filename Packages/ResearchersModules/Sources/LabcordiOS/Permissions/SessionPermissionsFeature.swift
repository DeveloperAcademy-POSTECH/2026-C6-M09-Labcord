import ComposableArchitecture
import LabcordShared

@Reducer
public struct SessionPermissionsFeature {
    @ObservableState
    public struct State: Equatable {
        public var camera = CameraPermssionFeature.State()
        public var microphoneStatus: PermissionStatus?
        public var speechRecognitionStatus: PermissionStatus?
        public var isRequesting = false
        public var issue: PermissionIssue?

        public init() {}
    }

    public enum Action: Equatable {
        case request
        case cancelRequest
        case camera(CameraPermssionFeature.Action)
        case microphoneStatusUpdated(PermissionStatus)
        case speechRecognitionStatusUpdated(PermissionStatus)
        case requestFinished
        case accessFailed(PermissionKind)
        case issueUpdated(PermissionIssue)
        case issueDismissed
        case openSettingsTapped
        case openSettingsFailed
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case request
    }

    @Dependency(\.cameraPermissionClient) var cameraPermissionClient
    @Dependency(\.microphonePermissionClient) var microphonePermissionClient
    @Dependency(\.speechRecognitionPermissionClient) var speechRecognitionPermissionClient
    @Dependency(\.permissionSettingsClient) var permissionSettingsClient

    public init() {}

    public var body: some Reducer<State, Action> {
        Scope(state: \.camera, action: \.camera) {
            CameraPermssionFeature()
        }

        Reduce { state, action in
            switch action {
            case .request:
                guard !state.isRequesting else { return .none }
                state.isRequesting = true
                state.issue = nil
                return .run { send in
                    let camera = await cameraPermissionClient.requestAccess()
                    guard !Task.isCancelled else { return }
                    await send(.camera(.statusUpdated(camera)))

                    let microphone = await microphonePermissionClient.requestAccess()
                    guard !Task.isCancelled else { return }
                    await send(.microphoneStatusUpdated(microphone))

                    let speechRecognition = await speechRecognitionPermissionClient.requestAccess()
                    guard !Task.isCancelled else { return }
                    await send(.speechRecognitionStatusUpdated(speechRecognition))
                    await send(.requestFinished)
                }
                .cancellable(id: CancelID.request, cancelInFlight: true)

            case .cancelRequest:
                state.isRequesting = false
                return .cancel(id: CancelID.request)

            case let .microphoneStatusUpdated(status):
                state.microphoneStatus = status
                return .none

            case let .speechRecognitionStatusUpdated(status):
                state.speechRecognitionStatus = status
                return .none

            case .requestFinished:
                state.isRequesting = false
                let requirements: [PermissionRequirement] = [
                    state.camera.status.map { .init(kind: .camera, status: $0) },
                    state.microphoneStatus.map { .init(kind: .microphone, status: $0) },
                    state.speechRecognitionStatus.map { .init(kind: .speechRecognition, status: $0) }
                ]
                .compactMap { $0 }
                .filter { $0.status == .denied || $0.status == .restricted }
                state.issue = requirements.isEmpty ? nil : .accessRequired(requirements)
                return .none

            case let .accessFailed(kind):
                return .run { send in
                    let status: PermissionStatus
                    switch kind {
                    case .camera:
                        status = await cameraPermissionClient.currentStatus()
                    case .microphone:
                        status = await microphonePermissionClient.currentStatus()
                    case .speechRecognition:
                        status = await speechRecognitionPermissionClient.currentStatus()
                    }
                    await send(.issueUpdated(.accessRequired([
                        PermissionRequirement(kind: kind, status: status)
                    ])))
                }

            case let .issueUpdated(issue):
                state.issue = issue
                return .none

            case .issueDismissed:
                state.issue = nil
                return .none

            case .openSettingsTapped:
                return .run { send in
                    guard await permissionSettingsClient.open() else {
                        await send(.openSettingsFailed)
                        return
                    }
                }

            case .openSettingsFailed:
                state.issue = .settingsUnavailable
                return .none

            case .camera:
                return .none
            }
        }
    }
}
