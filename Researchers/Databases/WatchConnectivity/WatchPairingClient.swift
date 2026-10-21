//
//  WatchPairingClient.swift
//  Researchers
//
//  Created by 정홍섭 on 10/21/26.
//

import Foundation
import WatchConnectivity

class WatchPairingClient: NSObject, WCSessionDelegate {
    private var onStatusChange: ((Bool?) -> Void)?
    
    func start(onStatusChange: @escaping (Bool?) -> Void) {
        self.onStatusChange = onStatusChange
        
        guard WCSession.isSupported() else {
            publish(false)
            return
        }
        
        let session = WCSession.default
        session.delegate = self
        
        if session.activationState == .activated {
            publish(session.isPaired)
        } else {
            publish(nil)
            session.activate()
        }
    }
    
    private func publish(_ status: Bool?) {
        DispatchQueue.main.async {
            self.onStatusChange?(status)
        }
    }
    
    func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        publish(state == .activated ? session.isPaired : nil)
    }
    
    func sessionWatchStateDidChange(_ session: WCSession) {
        guard session.activationState == .activated else { return }
        publish(session.isPaired)
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        publish(nil)
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        publish(nil)
        session.activate()
    }
}
