//
//  WatchBatteryClient.swift
//  Researchers
//
//  Created by 정홍섭 on 10/21/26.
//

import ComposableArchitecture
import Foundation
import Shared
import WatchConnectivity

final class WatchBatteryClient {
    private let connectivity: WatchConnectivitySession
    private var activationObserverID: UUID?
    
    init(connectivity: WatchConnectivitySession) {
        self.connectivity = connectivity
    }
    
    func requestBatteryLevel() {
        connectivity.activate()
        
        guard let session = connectivity.session else { return }
        
        if session.activationState == .activated {
            sendRequest(using: session)
            return
        }
        
        guard activationObserverID == nil else { return }
        
        activationObserverID = connectivity.addStateObserver { [weak self] in
            guard let self,
                  let session = self.connectivity.session,
                  session.activationState == .activated
                    else { return }
            
            if let id = self.activationObserverID {
                self.connectivity.removeStateObserver(id)
                self.activationObserverID = nil
            }
            
            self.sendRequest(using: session)
        }
    }
    
    private func sendRequest(using session: WCSession) {
        guard session.isPaired, session.isWatchAppInstalled else {
            return
        }
        
        session.transferUserInfo([
            WatchBatteryMessage.requestKey: true
        ])
    }
    
    func batteryStream() -> AsyncStream<Float?> {
        AsyncStream { continuation in
            let observerID = connectivity.addUserInfoObserver { userInfo in
                guard let number = userInfo[WatchBatteryMessage.levelKey] as? NSNumber
                        else { return }
                
                let level = number.floatValue
                continuation.yield(
                    (0...1).contains(level) ? level : nil
                )
            }
            
            continuation.onTermination = { [connectivity] _ in
                Task { @MainActor in
                    connectivity.removeUserInfoObserver(observerID)
                }
            }
        }
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
