//
//  WatchConnectivitySessionManaging.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/21/26.
//

import Foundation
import WatchConnectivity

@MainActor
public protocol WatchConnectivitySessionManaging: WCSessionDelegate {
    var observerStore: WatchConnectivityObserverStore { get }
}

extension WatchConnectivitySessionManaging {
    public var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    @discardableResult
    public func addUserInfoObserver(_ observer: @escaping ([String: Any]) -> Void) -> UUID {
        let id = observerStore.addUserInfoObserver(observer)
        activate()
        return id
    }

    public func removeUserInfoObserver(_ id: UUID) {
        observerStore.removeUserInfoObserver(id)
    }

    public func transferUserInfo(_ userInfo: [String: Any]) {
        guard let session, session.activationState == .activated else { return }
        session.transferUserInfo(userInfo)
    }

    public func activate() {
        guard let session else { return }

        session.delegate = self

        if session.activationState == .notActivated {
            session.activate()
        }
    }
}
