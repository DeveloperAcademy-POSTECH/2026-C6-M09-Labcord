import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

@Reducer
struct GesturePracticeFeature {
    @ObservableState
    struct State: Equatable {
        var device: GestureDevice
        var cameraStatus: PermissionStatus?
        var isRequestingPermissions = false
        var permissionIssue: PermissionIssue?
        /// AssistiveTouch 단축어로 인식된 마지막 Apple Watch 제스처입니다.
        var watchGesture: WatchGestureEvent?

        var permissionsGranted: Bool {
            cameraStatus == .authorized
        }
    }

    struct WatchGestureEvent: Equatable {
        let id: UUID
        let gesture: PracticeGesture
    }

    enum Action {
        case deviceChanged(GestureDevice)
        case watchGestureRecognized(PracticeGesture)
        case backTapped
        case exitTapped
        case practiceReady
        case requestPermissions
        case permissionsUpdated(PermissionStatus)
        case dismissPermissionIssue
        case openSettings
        case openSettingsFailed
    }

    @Dependency(\.cameraPermissionClient) private var cameraPermission
    @Dependency(\.permissionSettingsClient) private var permissionSettings
    @Dependency(\.uuid) private var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .deviceChanged(device):
                state.device = device
                return .none
            case let .watchGestureRecognized(gesture):
                state.watchGesture = WatchGestureEvent(id: uuid(), gesture: gesture)
                return .none
            case .requestPermissions:
                guard !state.isRequestingPermissions else { return .none }
                state.isRequestingPermissions = true
                state.permissionIssue = nil
                state.cameraStatus = nil
                return .run { send in
                    let camera = await cameraPermission.requestAccess()
                    guard !Task.isCancelled else { return }
                    if camera != .authorized {
                        try await Task.sleep(for: .milliseconds(500))
                    }
                    await send(.permissionsUpdated(camera))
                }
            case let .permissionsUpdated(camera):
                state.isRequestingPermissions = false
                state.cameraStatus = camera
                state.permissionIssue = camera == .authorized
                    ? nil : .accessRequired([.init(kind: .camera, status: camera)])
                return .none
            case .dismissPermissionIssue:
                state.permissionIssue = nil
                return .none
            case .openSettings:
                state.permissionIssue = nil
                return .run { send in
                    if !(await permissionSettings.open()) {
                        await send(.openSettingsFailed)
                    }
                }
            case .openSettingsFailed:
                state.permissionIssue = .settingsUnavailable
                return .none
            case .backTapped, .exitTapped, .practiceReady:
                return .none
            }
        }
    }
}
