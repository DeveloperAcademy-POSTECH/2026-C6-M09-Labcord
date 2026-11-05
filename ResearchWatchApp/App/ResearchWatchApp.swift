//
//  ResearchWatchApp.swift
//  ResearchWatch Watch App
//
//  Created by 정홍섭 on 10/18/26.
//

import SwiftUI

import ComposableArchitecture
import LabcordWatchOS

@main
struct ResearchWatchApp: App {
    @Dependency(\.watchBatteryClient) private var batteryClient
    @Dependency(\.watchDeviceNameClient) private var deviceNameClient
    @Dependency(\.watchConnectivitySession) var connectivity

    init() {
        batteryClient.start()
        deviceNameClient.start()
        WatchRecordingService.shared.activate()
    }

    private let store = Store(initialState: WatchExperimentFeature.State()) {
        WatchExperimentFeature(recordingBridge: .live)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
        .backgroundTask(.watchConnectivity) { [connectivity] in
            await connectivity.waitForPendingUserInfo()
        }
    }
}
