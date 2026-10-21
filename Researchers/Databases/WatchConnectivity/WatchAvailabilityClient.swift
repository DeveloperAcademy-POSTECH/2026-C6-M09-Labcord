//
//  WatchAvailabilityClient.swift
//  Researchers
//
//  Created by 정홍섭 on 10/21/26.
//

import Foundation
import WatchConnectivity
import ComposableArchitecture

final class WatchAvailabilityClient {
    private let connectivity: WatchConnectivitySession
    
    init(connectivity: WatchConnectivitySession) {
        self.connectivity = connectivity
    }
    
    func statusStream() -> AsyncStream<Bool?> {
        AsyncStream { continuation in
            let observerID = connectivity.addStateObserver {
                continuation.yield(self.currentReadiness())
            }
            
            continuation.onTermination = { [connectivity] _ in
                Task { @MainActor in
                    connectivity.removeStateObserver(observerID)
                }
            }
        }
    }
    
    private func currentReadiness() -> Bool? {
        guard let session = connectivity.session else {
            return false
        }
        
        guard session.activationState == .activated else {
            return nil
        }
        
        return session.isPaired && session.isWatchAppInstalled
    }
}

extension WatchAvailabilityClient: DependencyKey {
    static var liveValue: WatchAvailabilityClient {
        @Dependency(\.watchConnectivitySession) var connectivity
        
        return WatchAvailabilityClient(connectivity: connectivity)
    }
}

extension DependencyValues {
    var watchPairingClient: WatchAvailabilityClient {
        get { self[WatchAvailabilityClient.self] }
        set { self[WatchAvailabilityClient.self] = newValue }
    }
}
