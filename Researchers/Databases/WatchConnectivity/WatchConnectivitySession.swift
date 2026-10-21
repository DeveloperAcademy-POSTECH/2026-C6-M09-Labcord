//
//  WatchConnectivitySession.swift
//  Researchers
//
//  Created by 정홍섭 on 10/21/26.
//

import Foundation
import WatchConnectivity
import ComposableArchitecture

final class WatchConnectivitySession: NSObject, WCSessionDelegate {
    private let lock = NSLock()
    private var stateObservers: [UUID: () -> Void] = [:]
    var onUserInfoReceived: (([String: Any]) -> Void)?
    
    var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }
    
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
    
    func activate() {
        guard let session else { return }
        
        session.delegate = self
        
        if session.activationState == .notActivated {
            session.activate()
        }
    }
    
    private func notifyStateObservers() {
        lock.lock()
        let observers = Array(stateObservers.values)
        lock.unlock()
        
        DispatchQueue.main.async {
            observers.forEach { $0() }
        }
    }
    
    func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        notifyStateObservers()
    }
    
    func sessionWatchStateDidChange(_ session: WCSession) {
        notifyStateObservers()
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        notifyStateObservers()
    }

    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        DispatchQueue.main.async {
            self.onUserInfoReceived?(userInfo)
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        notifyStateObservers()
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        notifyStateObservers()
        session.activate()
    }
}

extension WatchConnectivitySession: DependencyKey {
    static let liveValue = WatchConnectivitySession()
}

extension DependencyValues {
    var watchConnectivitySession: WatchConnectivitySession {
        get { self[WatchConnectivitySession.self] }
        set { self[WatchConnectivitySession.self] = newValue }
    }
}
