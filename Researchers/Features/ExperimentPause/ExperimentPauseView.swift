//
//  ExperimentPauseView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/5/26.
//

import ComposableArchitecture
import LabcordiOS
import LabcordShared
import SwiftUI

struct ExperimentPauseView: View {
    let store: StoreOf<ExperimentPauseFeature>
    let timerStore: StoreOf<SessionTimerFeature>
    let canCloseSession: Bool

    private var displayedTimerCollection: ExperimentTimerCollection {
        guard timerStore.isSaving, let pendingSave = timerStore.pendingSave else {
            return timerStore.timerCollection
        }
        return pendingSave.collection
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let horizontalInset: CGFloat = 16
            let landscapeControlsScreenMargin: CGFloat = 62
            let controlsTrailingPadding = isLandscape
                ? landscapeControlsScreenMargin - horizontalInset
                    - geometry.safeAreaInsets.trailing
                : 0

            ZStack {
                Color("Experiment/Overlay/Scrim")
                    .background(
                        VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
                    )
                    .ignoresSafeArea()

                VStack(spacing: isLandscape ? 20 : 0) {
                    ExperimentPauseControlsView(store: store, canCloseSession: canCloseSession)
                        .padding(.top, isLandscape ? 0 : 16)
                        .padding(.trailing, controlsTrailingPadding)

                    if !isLandscape { Spacer() }

                    ExperimentPauseTimersView(
                        store: timerStore,
                        collection: displayedTimerCollection,
                        isLandscape: isLandscape,
                        availableWidth: geometry.size.width - horizontalInset * 2
                    )
                }
                .padding(.horizontal, horizontalInset)
                .padding(.top, isLandscape ? 20 : 0)
                .padding(.bottom, isLandscape ? 22 : 0)
            }
        }
        .alert(
            "실험 일시정지 저장 실패",
            isPresented: Binding(
                get: { store.exitFailed },
                set: { if !$0 { store.send(.dismissHomeExitFailure) } }
            )
        ) {
            Button("다시 시도") { store.send(.returnHomeTapped) }
            Button("닫기", role: .cancel) { store.send(.dismissHomeExitFailure) }
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
        timerStore: Store(initialState: SessionTimerFeature.State()) {
            SessionTimerFeature()
        },
        canCloseSession: true
    )
}
