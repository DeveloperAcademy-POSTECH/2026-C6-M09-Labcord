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

        public init() {}
    }

    public enum Action: Equatable {
        case request
        case cancelRequest
        case camera(CameraPermssionFeature.Action)
        case microphoneStatusUpdated(PermissionStatus)
        case speechRecognitionStatusUpdated(PermissionStatus)
        case requestFinished
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case request
    }

    @Dependency(\.cameraPermissionClient) var cameraPermissionClient
    @Dependency(\.microphonePermissionClient) var microphonePermissionClient
    @Dependency(\.speechRecognitionPermissionClient) var speechRecognitionPermissionClient

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
                return .none

            case .camera:
                return .none
            }
        }
    }
}
