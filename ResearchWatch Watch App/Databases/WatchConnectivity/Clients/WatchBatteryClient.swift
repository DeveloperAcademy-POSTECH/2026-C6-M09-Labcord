//
//  WatchBatteryClient.swift
//  ResearchWatch Watch App
//
//  Created by 정홍섭 on 10/21/26.
//

import ComposableArchitecture
import Foundation
import Shared
import WatchKit

final class WatchBatteryClient {
    private let connectivity: WatchConnectivitySession
    private var observerID: UUID?

    init(connectivity: WatchConnectivitySession) {
        self.connectivity = connectivity
    }

    func start() {
        guard observerID == nil else { return }

        // The session keeps this handler alive for background launches.
        observerID = connectivity.addUserInfoObserver { [self] userInfo in
            guard userInfo[WatchBatteryMessage.requestKey] as? Bool == true else {
                return
            }

            sendBatteryLevel()
        }
    }

    private func sendBatteryLevel() {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel

        connectivity.transferUserInfo([
            WatchBatteryMessage.levelKey: NSNumber(value: level)
        ])
    }
}

extension WatchBatteryClient: DependencyKey {
    static var liveValue: WatchBatteryClient {
        @Dependency(\.watchConnectivitySession) var connectivity

        return WatchBatteryClient(connectivity: connectivity)
    }
}

extension DependencyValues {
    var watchBatteryClient: WatchBatteryClient {
        get { self[WatchBatteryClient.self] }
        set { self[WatchBatteryClient.self] = newValue }
    }
}
