//
//  WatchConnectivityObserverStore.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/21/26.
//

import Foundation

private struct UserInfoDelivery: @unchecked Sendable {
    let userInfo: [String: Any]
    let observers: [([String: Any]) -> Void]
    let completion: () -> Void
}

public final class WatchConnectivityObserverStore: @unchecked Sendable {
    private let lock = NSLock()
    private var userInfoObservers: [UUID: ([String: Any]) -> Void] = [:]

    public init() {}

    public func addUserInfoObserver(_ observer: @escaping ([String: Any]) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        userInfoObservers[id] = observer
        lock.unlock()
        return id
    }

    public func removeUserInfoObserver(_ id: UUID) {
        lock.lock()
        userInfoObservers.removeValue(forKey: id)
        lock.unlock()
    }

    public func deliverUserInfo(
        _ userInfo: [String: Any],
        completion: @escaping () -> Void = {}
    ) {
        lock.lock()
        let observers = Array(userInfoObservers.values)
        lock.unlock()

        let delivery = UserInfoDelivery(
            userInfo: userInfo,
            observers: observers,
            completion: completion
        )

        DispatchQueue.main.async { [delivery] in
            delivery.observers.forEach { $0(delivery.userInfo) }
            delivery.completion()
        }
    }
}
