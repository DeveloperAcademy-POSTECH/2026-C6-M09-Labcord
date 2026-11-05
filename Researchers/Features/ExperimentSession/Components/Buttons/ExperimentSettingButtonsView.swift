//
//  ExperimentSettingButtonsView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/6/26.
//

import SwiftUI
import LabcordDesignSystem

struct ExperimentSettingButtonsView: View {
    var body: some View {
        HStack {
            ExperimentControlButton(action: {}) {
                Image(labcordIcon: .questionmark)
            }
            .background(
                VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            )
            .cornerRadius(LayoutTokens.radiusFull)
            
            Spacer()
            
            HStack(spacing: 20) {
                ExperimentControlButton(action: {}) {
                    Image(labcordIcon: .timer)
                        .foregroundStyle(Color("Experiment/Timer/Foreground"))
                }
                .background(
                    VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
                )
                .cornerRadius(LayoutTokens.radiusFull)
                
                ExperimentControlButton(action: {}) {
                    Image(labcordIcon: .arrowsCounterClockwise)
                }
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
    ExperimentSettingButtonsView()
        .background(.black)
}
