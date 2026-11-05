//
//  ExperimentPauseView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/5/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct ExperimentPauseView: View {
    let store: StoreOf<ExperimentPauseFeature>
    let canCloseSession: Bool

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

                    SlideToEndButton(
                        isTriggered: Binding(
                            get: { store.isEndTriggered },
                            set: { store.send(.endTriggerChanged($0)) }
                        )
                    ) {
                        store.send(.stopTapped)
                    }
                    .disabled(!canCloseSession)
                }
                .padding(.top, 16)

                Spacer()

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("진행 중인 타이머")
                            .typography(Typography.title3)
                            .foregroundStyle(Color("Experiment/Label/Primary"))

                        Text(
                            """
                            앱을 닫아도 타이머는 계속 진행돼요.
                            실험을 종료하면 진행 중인 타이머도 함께 종료돼요.
                            """
                        )
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
        .alert(
            "실험 일시정지 저장 실패",
            isPresented: Binding(
                get: { store.exitFailed },
                set: { if !$0 { store.send(.dismissHomeExitFailure) } }
            )
        ) {
            Button("다시 시도") {
                store.send(.returnHomeTapped)
            }
            Button("닫기", role: .cancel) {
                store.send(.dismissHomeExitFailure)
            }
        } message: {
            Text("실험 상태를 저장하지 못했습니다.")
        }
    }
}

#Preview {
    ExperimentPauseView(
        store: Store(
            initialState: ExperimentPauseFeature.State(experimentID: UUID())
        ) {
            ExperimentPauseFeature()
        },
        canCloseSession: true
    )
}
