//
//  WatchResponseStream.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/23/26.
//

import Foundation
import LabcordShared

enum WatchResponseStream {
    static func make<Value>(
        connectivity: WatchConnectivitySession,
        decode: @escaping ([String: Any]) -> Value?
    ) -> AsyncStream<Value> {
        AsyncStream { continuation in
            let observerID = connectivity.addUserInfoObserver { userInfo in
                guard let value = decode(userInfo) else { return }
                continuation.yield(value)
            }

            continuation.onTermination = { [connectivity] _ in
                Task { @MainActor in
                    connectivity.removeUserInfoObserver(observerID)
                }
            }
        }
    }
}
