//
//  ExperimentRecordButtonsView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/6/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct ExperimentRecordButtonsView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let store: StoreOf<CameraCaptureFeature>
    let isDisabled: Bool

    var body: some View {
        let isLandscape = verticalSizeClass == .compact
        let layout = isLandscape
            ? AnyLayout(HStackLayout(spacing: 24))
            : AnyLayout(VStackLayout(spacing: 24))

        layout {
            RecordButton(
                type: .audio,
                state: isDisabled ? .disabled : .default
            ) { store.send(.voiceButtonTapped) }
            .background(
                VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            )
            .cornerRadius(LayoutTokens.radiusFull)

            RecordButton(
                type: .capture,
                state: isDisabled ? .disabled : .default
            ) { store.send(.photoButtonTapped) }
            .background(
                VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            )
            .cornerRadius(LayoutTokens.radiusFull)

            RecordButton(
                type: .video,
                state: isDisabled ? .disabled : .default
            ) { store.send(.videoButtonTapped) }
            .background(
                VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            )
            .cornerRadius(LayoutTokens.radiusFull)
        }
        .padding(.horizontal, isLandscape ? 0 : 16)
        .padding(.top, isLandscape ? 20 : 0)
    }
}

#Preview {
    ExperimentRecordButtonsView(
        store: Store(initialState: CameraCaptureFeature.State(experimentID: UUID())) {
            CameraCaptureFeature()
        },
        isDisabled: false
    )
    .background(.black)
}
