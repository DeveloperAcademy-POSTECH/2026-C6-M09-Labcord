//
//  WatchBatteryClient.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/21/26.
//

#if os(watchOS)
import ComposableArchitecture
import Foundation
import LabcordShared
import WatchKit

public final class WatchBatteryClient {
    private let responder: WatchRequestResponder

    init(connectivity: WatchConnectivitySession) {
        self.responder = WatchRequestResponder(
            connectivity: connectivity,
            requestKey: WatchBatteryMessage.requestKey
        ) {
            let device = WKInterfaceDevice.current()
            device.isBatteryMonitoringEnabled = true
            return [WatchBatteryMessage.levelKey: NSNumber(value: device.batteryLevel)]
        }
    }

    public func start() {
        responder.start()
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
#endif
