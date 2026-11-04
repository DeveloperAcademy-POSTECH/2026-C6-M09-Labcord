//
//  OnboardingSkipRow.swift
//  Researchers
//
//  Created by lwc0113 on 11/4/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct OnboardingSkipRow: View {
    let store: StoreOf<OnboardingFeature>

    var body: some View {
        HStack {
            Spacer()
            Button("건너뛰기") { store.send(.skipTapped) }
            .buttonStyle(IOSButtonStyle(.accent, size: .medium))
            .opacity(store.page == .third ? 0 : 1)
            .disabled(store.page == .third)
        }
    }
}
