//
//  ExperimentSettingButtonsView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/6/26.
//

import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct ExperimentSettingButtonsView: View {
    let onShowGestureGuide: () -> Void
    let onShowRunningTimers: () -> Void
    let onSwitchCamera: () -> Void
    let showsRunningTimerButton: Bool
    let canSwitchCamera: Bool

    var body: some View {
        HStack {
            ExperimentControlButton(action: onShowGestureGuide) {
                Image(labcordIcon: .questionmark)
            }
            .accessibilityLabel("제스처 안내")
            .background(
                VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            )
            .cornerRadius(LayoutTokens.radiusFull)

            Spacer()

            HStack(spacing: 20) {
                if showsRunningTimerButton {
                    TimerControlButton(state: .running, action: onShowRunningTimers)
                        .background(
                            VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
                        )
                        .cornerRadius(LayoutTokens.radiusFull)
                }

                ExperimentControlButton(
                    state: canSwitchCamera ? .default : .disabled,
                    action: onSwitchCamera
                ) {
                    Image(labcordIcon: .arrowsCounterClockwise)
                }
                .accessibilityLabel("카메라 전환")
                .background(
                    VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
                )
                .cornerRadius(LayoutTokens.radiusFull)

                ExperimentControlButton(
                    action: {},
                    icon: { Image(labcordIcon: .rectanglePortraitRotate) }
                )
                .background(
                    VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
                )
                .cornerRadius(LayoutTokens.radiusFull)
            }
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    ExperimentSettingButtonsView(
        onShowGestureGuide: {},
        onShowRunningTimers: {},
        onSwitchCamera: {},
        showsRunningTimerButton: true,
        canSwitchCamera: true
    )
        .background(.black)
}
