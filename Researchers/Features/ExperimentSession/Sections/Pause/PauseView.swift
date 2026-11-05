//
//  PauseView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/5/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI
import UIKit

struct PauseView: View {
    let store: StoreOf<ExperimentSessionFeature>

    @State private var isEndTriggered = false

    var body: some View {
        ZStack {
            Color("Experiment/Overlay/Scrim")
                .background(
                    VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
                )
                .ignoresSafeArea()

            VStack {
                HStack(spacing: 8) {
                    Button {
                        store.send(.resumeTapped)
                    } label: {
                        Image(labcordIcon: .play)
                            .foregroundStyle(Color("Experiment/Label/Primary"))
                    }
                    .buttonStyle(.labcordIcon(.neutral, size: .large))

                    Button {
                        store.send(.returnHomeTapped)
                    } label: {
                        Text("홈으로 이동")
                            .foregroundStyle(Color("Experiment/Label/Primary"))
                    }
                    .buttonStyle(.labcord(.plain, size: .medium))

                    Spacer()

                    SlideToEndButton(isTriggered: $isEndTriggered) {
                        store.send(.stopTapped)
                    }
                    .disabled(!store.canCloseSession)
                }
                .padding(.top, 16)

                Spacer()

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("진행 중인 타이머")
                            .typography(Typography.title3)
                            .foregroundStyle(Color("Experiment/Label/Primary"))

                        Text("앱을 닫아도 타이머는 계속 진행돼요.\n실험을 종료하면 진행 중인 타이머도 함께 종료돼요.")
                            .typography(Typography.callout)
                            .foregroundStyle(Color("Experiment/Label/Secondary"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

//                    VStack {
//
//                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .onChange(of: store.completionFailed) { _, failed in
            if failed {
                isEndTriggered = false
            }
        }
    }
}

#Preview {
    PauseView(
        store: Store(
            initialState: ExperimentSessionFeature.State(experimentID: UUID())
        ) {
            ExperimentSessionFeature()
        }
    )
}
