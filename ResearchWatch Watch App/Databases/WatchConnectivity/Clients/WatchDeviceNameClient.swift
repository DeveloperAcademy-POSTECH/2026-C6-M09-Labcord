import ComposableArchitecture
import Foundation
import Shared
import WatchKit

final class WatchDeviceNameClient {
    private let connectivity: WatchConnectivitySession
    private var observerID: UUID?

    init(connectivity: WatchConnectivitySession) {
        self.connectivity = connectivity
    }

    func start() {
        guard observerID == nil else { return }

        // The session keeps this handler alive for background launches.
        observerID = connectivity.addUserInfoObserver { [self] userInfo in
            guard userInfo[WatchDeviceNameMessage.requestKey] as? Bool == true else {
                return
            }

            sendDeviceName()
        }
    }

    private func sendDeviceName() {
        connectivity.transferUserInfo([
            WatchDeviceNameMessage.nameKey: WKInterfaceDevice.current().model
        ])
    }
}

extension WatchDeviceNameClient: DependencyKey {
    static var liveValue: WatchDeviceNameClient {
        @Dependency(\.watchConnectivitySession) var connectivity
        return WatchDeviceNameClient(connectivity: connectivity)
    }
}

extension DependencyValues {
    var watchDeviceNameClient: WatchDeviceNameClient {
        get { self[WatchDeviceNameClient.self] }
        set { self[WatchDeviceNameClient.self] = newValue }
    }
}
