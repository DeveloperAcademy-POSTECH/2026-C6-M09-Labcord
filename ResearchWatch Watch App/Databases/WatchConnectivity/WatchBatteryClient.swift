//
//  WatchBatteryClient.swift
//  ResearchWatch Watch App
//
//  Created by 정홍섭 on 10/21/26.
//

import ComposableArchitecture
import Foundation
import Shared
import WatchConnectivity
import WatchKit

final class WatchBatteryClient {
    private let connectivity: WatchConnectivitySession
    
    init(connectivity: WatchConnectivitySession) {
        self.connectivity = connectivity
    }
    
    func start() {
        connectivity.onUserInfoReceived = { [weak self] userInfo in
            guard userInfo[WatchBatteryMessage.requestKey] as? Bool == true else {
                return
            }
            
            self?.sendBatteryLevel()
        }
        
        connectivity.activate()
    }
    
    private func sendBatteryLevel() {
        guard let session = connectivity.session, session.activationState == .activated else {
            return
        }
        
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        
        session.transferUserInfo([
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
