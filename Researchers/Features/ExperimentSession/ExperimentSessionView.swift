//
//  ExperimentSessionView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import SwiftUI

struct ExperimentSessionView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        if verticalSizeClass == .compact {
            LandscapeSessionView()
        } else {
            PortraitSessionView()
        }
    }
}

#Preview {
    ExperimentSessionView()
}
