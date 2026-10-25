//
//  ExperimentSessionView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import SwiftUI

struct ExperimentSessionView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var store = Store(initialState: ExperimentSessionFeature.State()) {
        ExperimentSessionFeature()
    }

    var body: some View {
        if verticalSizeClass == .compact {
            LandscapeSessionView(store: store)
        } else {
            PortraitSessionView(store: store)
        }
    }
}

#Preview {
    ExperimentSessionView()
}
