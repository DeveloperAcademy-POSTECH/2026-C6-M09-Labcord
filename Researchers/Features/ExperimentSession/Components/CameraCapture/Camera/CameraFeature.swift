import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

@Reducer
struct CameraFeature {
    @ObservableState
    struct State: Equatable {
        var ownerID = UUID()
        var isViewVisible = false
        var errorMessage: String?
        var previewConnector: CameraPreviewConnector?
        var isSwitching = false
    }

    enum Action: Equatable {
        case viewAppeared
        case viewDisappeared
        case activationRequested
        case started(UUID, CameraPreviewConnector)
        case startFailed(UUID, String)
        case switchRequested
        case switched(CameraPreviewConnector)
        case switchFailed(String)
        case errorDismissed
        case handEvent(CameraHandEvent)
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case permissionAccessFailed(PermissionKind)
        case handEvent(CameraHandEvent)
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case handTracking
    }

    @Dependency(\.cameraSessionClient) var cameraSessionClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .viewAppeared:
                guard !state.isViewVisible else { return .none }
                state.isViewVisible = true
                state.ownerID = UUID()
                return .none

            case .viewDisappeared:
                guard state.isViewVisible else { return .none }
                state.isViewVisible = false
                state.previewConnector = nil
                let ownerID = state.ownerID
                return .merge(
                    .cancel(id: CancelID.handTracking),
                    .run { _ in await cameraSessionClient.deactivate(ownerID) }
                )

            case .activationRequested:
                guard state.isViewVisible else { return .none }
                let ownerID = state.ownerID
                return .run { send in
                    do {
                        try await cameraSessionClient.activate(ownerID)
                        let connector = await cameraSessionClient.previewConnector()
                        await send(.started(ownerID, connector))
                    } catch let error as PermissionAccessError {
                        await send(.delegate(.permissionAccessFailed(error.kind)))
                    } catch {
                        await send(.startFailed(ownerID, error.localizedDescription))
                    }
                }

            case let .started(ownerID, connector):
                guard state.isViewVisible, ownerID == state.ownerID else {
                    return .run { _ in await cameraSessionClient.deactivate(ownerID) }
                }
                state.errorMessage = nil
                state.previewConnector = connector
                return .run { send in
                    for await event in await cameraSessionClient.handEvents() {
                        await send(.handEvent(event))
                    }
                }
                .cancellable(id: CancelID.handTracking, cancelInFlight: true)

            case .switchRequested:
                guard state.isViewVisible, state.previewConnector != nil,
                      !state.isSwitching else { return .none }
                state.isSwitching = true
                return .run { send in
                    do {
                        try await cameraSessionClient.switchCamera()
                        let connector = await cameraSessionClient.previewConnector()
                        await send(.switched(connector))
                    } catch {
                        await send(.switchFailed(error.localizedDescription))
                    }
                }

            case let .switched(connector):
                state.isSwitching = false
                guard state.isViewVisible else { return .none }
                state.errorMessage = nil
                state.previewConnector = connector
                return .none

            case let .startFailed(ownerID, message):
                guard state.isViewVisible, ownerID == state.ownerID else { return .none }
                state.errorMessage = message
                return .none

            case let .switchFailed(message):
                state.isSwitching = false
                guard state.isViewVisible else { return .none }
                state.errorMessage = message
                return .none

            case .errorDismissed:
                state.errorMessage = nil
                return .none

            case let .handEvent(event):
                guard state.isViewVisible else { return .none }
                return .send(.delegate(.handEvent(event)))

            case .delegate:
                return .none
            }
        }
    }
}
