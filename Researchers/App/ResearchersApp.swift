//
//  ResearchersApp.swift
//  Researchers
//
//  Created by 정홍섭 on 10/15/26.
//

import SwiftUI
import ComposableArchitecture

@main
struct ResearchersApp: App {
    var body: some Scene {
        WindowGroup {
            WatchPairingView(
                store: Store(initialState: WatchPairingFeature.State()) {
                    WatchPairingFeature()
                }
            )
        }
    }
}
