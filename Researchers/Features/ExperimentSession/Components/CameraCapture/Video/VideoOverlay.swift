//
//  VideoOverlay.swift
//  Researchers
//
//  Created by 정홍섭 on 11/13/26.
//

import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct VideoOverlay: View {
    let connector: CameraPreviewConnector
    let onCancel: () -> Void
    let onStop: () -> Void

    @State private var isStopping = false

    var body: some View {
        CapturedMediaOverlay {
            CameraPreviewView(connector: connector, showsHandOverlay: false)
                .transaction { $0.disablesAnimations = true }
        } controls: {
            VStack {
                HStack(spacing: 12) {
                    ExperimentControlButton(action: onCancel) {
                        Image(labcordIcon: .x)
                    }
                    .accessibilityLabel("영상 촬영 취소")
                    .background(
                        VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
                    )
                    .cornerRadius(LayoutTokens.radiusFull)

                    Text("영상 기록")
                        .typography(Typography.headline)
                        .foregroundStyle(Color("Experiment/Label/Primary"))

                    Spacer()
                }

                Spacer()

                Button(role: .destructive) {
                    isStopping = true
                    onStop()
                } label: {
                    Image(labcordIcon: .stop)
                }
                .buttonStyle(
                    .labcordIcon(.filled, size: .extraLarge, colorPalette: .experiment)
                )
                .disabled(isStopping)
            }
            .padding(16)
        }
    }
}
