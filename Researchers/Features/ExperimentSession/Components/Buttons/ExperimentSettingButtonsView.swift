//
//  ExperimentSettingButtonsView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/6/26.
//

import SwiftUI
import LabcordDesignSystem

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
                    ExperimentControlButton(action: onShowRunningTimers) {
                        Image(labcordIcon: .timer)
                            .foregroundStyle(Color("Experiment/Timer/Foreground"))
                    }
                    .accessibilityLabel("진행 중인 타이머 보기")
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
                
                ExperimentControlButton(action: {}) {
                    Image(labcordIcon: .rectanglePortraitRotate)
                }
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
