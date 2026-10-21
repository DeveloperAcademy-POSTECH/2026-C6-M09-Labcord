//
//  WatchConnectivitySession.swift
//  ResearchWatch Watch App
//
//  Created by 정홍섭 on 10/21/26.
//

import ComposableArchitecture
import Foundation
import WatchConnectivity

final class WatchConnectivitySession: NSObject, WCSessionDelegate {
    private let deliveryLock = NSLock()
    private var handlingUserInfoCount = 0
    private var lastHandledUserInfoAt: Date?
    private var userInfoObservers: [UUID: ([String: Any]) -> Void] = [:]
    
    private func deliveryState(since start: Date) -> (isHandling: Bool, handledRecently: Bool) {
        deliveryLock.lock()
        defer { deliveryLock.unlock() }
        return (
            handlingUserInfoCount > 0,
            lastHandledUserInfoAt.map { $0 >= start.addingTimeInterval(-1) } ?? false
        )
    }
    
    var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }
    
    @discardableResult
    func addUserInfoObserver(_ observer: @escaping ([String: Any]) -> Void) -> UUID {
        let id = UUID()

        deliveryLock.lock()
        userInfoObservers[id] = observer
        deliveryLock.unlock()

        activate()
        return id
    }

    func removeUserInfoObserver(_ id: UUID) {
        deliveryLock.lock()
        userInfoObservers.removeValue(forKey: id)
        deliveryLock.unlock()
    }

    func transferUserInfo(_ userInfo: [String: Any]) {
        guard let session, session.activationState == .activated else { return }
        session.transferUserInfo(userInfo)
    }
    
    func activate() {
        guard let session else { return }
        
        session.delegate = self
        
        if session.activationState == .notActivated {
            session.activate()
        }
    }
    
    func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {}
    
    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        deliveryLock.lock()
        handlingUserInfoCount += 1
        deliveryLock.unlock()
        
        DispatchQueue.main.async {
            self.deliveryLock.lock()
            let observers = Array(self.userInfoObservers.values)
            self.deliveryLock.unlock()

            observers.forEach { $0(userInfo) }

            self.deliveryLock.lock()
            self.handlingUserInfoCount -= 1
            self.lastHandledUserInfoAt = Date()
            self.deliveryLock.unlock()
        }
    }
    
    func waitForPendingUserInfo() async {
        activate()
        let start = Date()
        let deadline = start.addingTimeInterval(5)
        
        while !Task.isCancelled {
            guard let session else { return }

            let hasContentPending = session.hasContentPending
            let delivery = deliveryState(since: start)

            if session.activationState == .activated,
               !hasContentPending,
               !delivery.isHandling,
               delivery.handledRecently {
                return
            }

            guard Date() < deadline else { return }
            
            try? await Task.sleep(for: .milliseconds(30))
        }
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
