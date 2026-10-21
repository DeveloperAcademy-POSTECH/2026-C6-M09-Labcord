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
    
    func startObservingStatus(onStatusChange: @escaping (Bool?) -> Void) {
        self.onStatusChange = onStatusChange
        
        guard WCSession.isSupported() else {
            sendCurrentStatus()
            return
        }
        
        let session = WCSession.default
        session.delegate = self
        
        sendCurrentStatus()
        
        if session.activationState != .activated {
            session.activate()
        }
    }
    
    private func sendCurrentStatus() {
        let status: Bool?
        
        if !WCSession.isSupported() {
            status = false
        } else {
            let session = WCSession.default
            status = session.activationState == .activated ? session.isPaired && session.isWatchAppInstalled : nil
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
        sendCurrentStatus()
    }
    
    func sessionWatchStateDidChange(_ session: WCSession) {
        sendCurrentStatus()
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        sendCurrentStatus()
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        sendCurrentStatus()
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        sendCurrentStatus()
        session.activate()
    }
    
    func statusStream() -> AsyncStream<Bool?> {
        AsyncStream { continuation in
            startObservingStatus { status in
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
