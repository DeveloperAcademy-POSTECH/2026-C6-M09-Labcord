import ComposableArchitecture
import Foundation
import LabcordShared
import WatchConnectivity

public final class WatchDeviceNameClient {
    private let connectivity: WatchConnectivitySession
    private var activationObserverID: UUID?

    init(connectivity: WatchConnectivitySession) {
        self.connectivity = connectivity
    }

    public func requestDeviceName() {
        connectivity.activate()

        guard let session = connectivity.session else { return }

        if sendRequestIfReady(using: session) {
            cancelRequest()
            return
        }

        guard activationObserverID == nil else { return }

        activationObserverID = connectivity.addStateObserver { [weak self] in
            guard let self,
                  self.activationObserverID != nil,
                  let session = self.connectivity.session,
                  self.sendRequestIfReady(using: session) else { return }

            self.cancelRequest()
        }
    }

    public func cancelRequest() {
        guard let id = activationObserverID else { return }
        connectivity.removeStateObserver(id)
        activationObserverID = nil
    }

    @discardableResult
    private func sendRequestIfReady(using session: WCSession) -> Bool {
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else { return false }

        session.transferUserInfo([
            WatchDeviceNameMessage.requestKey: true
        ])
        return true
    }

    public func deviceNameStream() -> AsyncStream<String> {
        AsyncStream { continuation in
            let observerID = connectivity.addUserInfoObserver { userInfo in
                guard let name = userInfo[WatchDeviceNameMessage.nameKey] as? String,
                      !name.isEmpty else { return }

                continuation.yield(name)
            }

            continuation.onTermination = { [connectivity] _ in
                Task { @MainActor in
                    connectivity.removeUserInfoObserver(observerID)
                }
            }
        }
    }
}

extension WatchDeviceNameClient: DependencyKey {
    public static var liveValue: WatchDeviceNameClient {
        @Dependency(\.watchConnectivitySession) var connectivity
        return WatchDeviceNameClient(connectivity: connectivity)
    }
}

extension DependencyValues {
    public var watchDeviceNameClient: WatchDeviceNameClient {
        get { self[WatchDeviceNameClient.self] }
        set { self[WatchDeviceNameClient.self] = newValue }
    }
}
