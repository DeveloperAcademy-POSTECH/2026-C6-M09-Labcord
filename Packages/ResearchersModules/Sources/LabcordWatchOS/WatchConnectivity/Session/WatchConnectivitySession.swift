//
//  WatchConnectivitySession.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/21/26.
//

import ComposableArchitecture
import Foundation
import LabcordShared
import WatchConnectivity

public final class WatchConnectivitySession: NSObject, WatchConnectivitySessionManaging {
    private let deliveryLock = NSLock()
    private var handlingUserInfoCount = 0
    private var lastHandledUserInfoAt: Date?
    public let observerStore = WatchConnectivityObserverStore()

    private func deliveryState(since start: Date) -> (isHandling: Bool, handledRecently: Bool) {
        deliveryLock.lock()
        defer { deliveryLock.unlock() }
        return (
            handlingUserInfoCount > 0,
            lastHandledUserInfoAt.map { $0 >= start.addingTimeInterval(-1) } ?? false
        )
    }

    public func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {}

    public func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        deliveryLock.lock()
        handlingUserInfoCount += 1
        deliveryLock.unlock()

        observerStore.deliverUserInfo(userInfo) {
            self.deliveryLock.lock()
            self.handlingUserInfoCount -= 1
            self.lastHandledUserInfoAt = Date()
            self.deliveryLock.unlock()
        }
    }

    public func waitForPendingUserInfo() async {
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
    public static let liveValue = WatchConnectivitySession()
}

extension DependencyValues {
    public var watchConnectivitySession: WatchConnectivitySession {
        get { self[WatchConnectivitySession.self] }
        set { self[WatchConnectivitySession.self] = newValue }
    }
}
