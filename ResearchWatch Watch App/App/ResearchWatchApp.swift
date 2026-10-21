//
//  ResearchWatchApp.swift
//  ResearchWatch Watch App
//
//  Created by 정홍섭 on 10/18/26.
//

import SwiftUI

import ComposableArchitecture

@main
struct ResearchWatchApp: App {
    @Dependency(\.watchBatteryClient) private var batteryClient
    @Dependency(\.watchConnectivitySession) var connectivity
    
    init() {
        batteryClient.start()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .backgroundTask(.watchConnectivity) { [connectivity] in
            await connectivity.waitForPendingUserInfo()
        }
    }
}
