//
//  ExperimentSessionView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import SwiftUI
import LabcordiOS

struct ExperimentSessionView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    @State private var store = Store(initialState: ExperimentSessionFeature.State()) {
        ExperimentSessionFeature()
    }
    
    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                LandscapeSessionView(store: store)
            } else {
                PortraitSessionView(store: store)
            }
        }
        .task {
            store.send(.cameraPermission(.request))
        }
    }
}

#Preview {
    ExperimentSessionView()
}
