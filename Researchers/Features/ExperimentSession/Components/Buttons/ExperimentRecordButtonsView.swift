//
//  ExperimentRecordButtonsView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/6/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct ExperimentRecordButtonsView: View {
    let store: StoreOf<CameraCaptureFeature>
    let isDisabled: Bool

    var body: some View {
        VStack(spacing: 24) {
            RecordButton(
                type: .audio,
                state: isDisabled ? .disabled : .default,
                action: { store.send(.voiceButtonTapped) }
            )
            .background(
                VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            )
            .cornerRadius(LayoutTokens.radiusFull)

            RecordButton(
                type: .capture,
                state: isDisabled ? .disabled : .default,
                action: { store.send(.photoButtonTapped) }
            )
            .background(
                VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            )
            .cornerRadius(LayoutTokens.radiusFull)

            RecordButton(
                type: .video,
                state: isDisabled ? .disabled : .default,
                action: { store.send(.videoButtonTapped) }
            )
            .background(
                VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            )
            .cornerRadius(LayoutTokens.radiusFull)
        }
        .padding(.horizontal, 16)
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
