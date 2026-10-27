//
//  ResearchersApp.swift
//  Researchers
//
//  Created by 정홍섭 on 10/15/26.
//

import ComposableArchitecture
import SwiftUI

@main
struct ResearchersApp: App {
    @State private var store = Store(initialState: ExperimentEntryFeature.State()) {
        ExperimentEntryFeature()
    }

    var body: some Scene {
        WindowGroup {
            ExperimentEntryView(store: store)
        }
    }
}
