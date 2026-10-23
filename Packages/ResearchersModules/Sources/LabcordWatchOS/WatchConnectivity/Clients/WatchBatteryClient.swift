//
//  WatchBatteryClient.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/21/26.
//

import ComposableArchitecture
import Foundation
import LabcordShared
import WatchKit

public final class WatchBatteryClient {
    private let connectivity: WatchConnectivitySession
    private var observerID: UUID?

    init(connectivity: WatchConnectivitySession) {
        self.connectivity = connectivity
    }

    public func start() {
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
    public static var liveValue: WatchBatteryClient {
        @Dependency(\.watchConnectivitySession) var connectivity

        return WatchBatteryClient(connectivity: connectivity)
    }
}

extension DependencyValues {
    public var watchBatteryClient: WatchBatteryClient {
        get { self[WatchBatteryClient.self] }
        set { self[WatchBatteryClient.self] = newValue }
    }
}
