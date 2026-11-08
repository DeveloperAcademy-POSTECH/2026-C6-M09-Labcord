import ComposableArchitecture
import Foundation
import LabcordShared
import WatchConnectivity

public final class WatchConnectivitySession: NSObject, WatchConnectivitySessionManaging {
    private let lock = NSLock()
    private var stateObservers: [UUID: () -> Void] = [:]
    public let observerStore = WatchConnectivityObserverStore()
    public let experiments = WatchExperimentTransport()

    func addStateObserver(_ observer: @escaping () -> Void) -> UUID {
        let id = UUID()

        lock.lock()
        stateObservers[id] = observer
        lock.unlock()

        activate()

        DispatchQueue.main.async {
            observer()
        }

        return id
    }

    func removeStateObserver(_ id: UUID) {
        lock.lock()
        stateObservers.removeValue(forKey: id)
        lock.unlock()
    }

    private func notifyStateObservers() {
        lock.lock()
        let observers = Array(stateObservers.values)
        lock.unlock()

        DispatchQueue.main.async {
            observers.forEach { $0() }
        }
    }

    public func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        notifyStateObservers()
    }

    public func sessionWatchStateDidChange(_ session: WCSession) {
        notifyStateObservers()
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        notifyStateObservers()
    }

    public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let data = message[WatchExperimentTransport.commandKey] as? Data
        Task { @MainActor in
            let response = data.flatMap { experiments.reply(to: $0) }
            replyHandler(response.map { [WatchExperimentTransport.responseKey: $0] } ?? [:])
        }
    }

    public func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext[WatchExperimentTransport.snapshotKey] as? Data
        else { return }
        Task { @MainActor in experiments.receiveSnapshot(data) }
    }

    public func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        observerStore.deliverUserInfo(userInfo)
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {
        notifyStateObservers()
    }

    public func sessionDidDeactivate(_ session: WCSession) {
        notifyStateObservers()
        session.activate()
    }
}

extension WatchConnectivitySession: DependencyKey {
    public static let liveValue = WatchConnectivitySession()
}

extension DependencyValues {
    public var watchConnectivitySession: WatchConnectivitySession {
        get { self[WatchConnectivitySession.self] }
        set { self[WatchConnectivitySession.self] = newValue }
    }
}
