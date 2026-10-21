//
//  WatchPairingClient.swift
//  Researchers
//
//  Created by 정홍섭 on 10/21/26.
//

import Foundation
import WatchConnectivity
import ComposableArchitecture

class WatchPairingClient: NSObject, WCSessionDelegate {
    private var onStatusChange: ((Bool?) -> Void)?
    
    func start(onStatusChange: @escaping (Bool?) -> Void) {
        self.onStatusChange = onStatusChange
        
        guard WCSession.isSupported() else {
            publish()
            return
        }
        
        let session = WCSession.default
        session.delegate = self
        
        publish()
        
        if session.activationState != .activated {
            session.activate()
        }
    }
    
    private func publish() {
        let status: Bool?
        
        if !WCSession.isSupported() {
            status = false
        } else {
            let session = WCSession.default
            status = session.activationState == .activated ? session.isPaired && session.isReachable : nil
        }
        
        DispatchQueue.main.async {
            self.onStatusChange?(status)
        }
    }
    
    func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        publish()
    }
    
    func sessionWatchStateDidChange(_ session: WCSession) {
        publish()
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        publish()
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        publish()
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        publish()
        session.activate()
    }
    
    func statusStream() -> AsyncStream<Bool?> {
        AsyncStream { continuation in
            start { status in
                continuation.yield(status)
            }
            
            continuation.onTermination = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.onStatusChange = nil
                }
            }
        }
    }
}

extension WatchPairingClient: DependencyKey {
    static let liveValue: WatchPairingClient = WatchPairingClient()
}

extension DependencyValues {
    var watchPairingClient: WatchPairingClient {
        get { self[WatchPairingClient.self] }
        set { self[WatchPairingClient.self] = newValue }
    }
}
