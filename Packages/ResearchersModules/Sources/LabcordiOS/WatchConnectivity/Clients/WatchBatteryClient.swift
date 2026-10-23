//
//  WatchBatteryClient.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/21/26.
//

import ComposableArchitecture
import Foundation
import LabcordShared

public final class WatchBatteryClient {
    private let connectivity: WatchConnectivitySession
    private let requestSender: WatchRequestSender

    init(connectivity: WatchConnectivitySession) {
        self.connectivity = connectivity
        self.requestSender = WatchRequestSender(
            connectivity: connectivity,
            requestKey: WatchBatteryMessage.requestKey
        )
    }

    public func requestBatteryLevel() {
        requestSender.request()
    }

    public func cancelRequest() {
        requestSender.cancel()
    }

    public func batteryStream() -> AsyncStream<Float?> {
        WatchResponseStream.make(connectivity: connectivity) { [requestSender] userInfo -> Float?? in
            guard requestSender.matchesResponse(userInfo),
                  let number = userInfo[WatchBatteryMessage.levelKey] as? NSNumber else {
                return nil
            }

            let level = number.floatValue
            return .some((0...1).contains(level) ? level : nil)
        }
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
