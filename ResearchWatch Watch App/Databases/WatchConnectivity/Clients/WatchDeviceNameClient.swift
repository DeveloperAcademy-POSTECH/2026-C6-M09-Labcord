import ComposableArchitecture
import DeviceKit
import Foundation
import LabcordShared
import WatchKit

final class WatchDeviceNameClient {
    private let connectivity: WatchConnectivitySession
    private var observerID: UUID?

    init(connectivity: WatchConnectivitySession) {
        self.connectivity = connectivity
    }

    func start() {
        guard observerID == nil else { return }

        observerID = connectivity.addUserInfoObserver { [self] userInfo in
            guard userInfo[WatchDeviceNameMessage.requestKey] as? Bool == true else {
                return
            }

            sendDeviceName()
        }
    }

    private func sendDeviceName() {
        let modelName = Device.realDevice(from: .current).description
            .replacingOccurrences(of: #"\d+mm$"#, with: "", options: .regularExpression )

        connectivity.transferUserInfo([
            WatchDeviceNameMessage.nameKey: modelName
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
