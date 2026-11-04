//
//  ExperimentResultView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/29/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct ExperimentResultView: View {
    let store: StoreOf<ExperimentResultFeature>

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color("General/Background/Primary")
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Group {
                        if store.recordTimeline == nil && store.loadMessage == nil {
                            ExperimentProcessingView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                NavigationPageTitle(
                                    "실험 기록",
                                    onBack: store.isOpenedFromHome
                                        ? { store.send(.homeTapped) } : nil
                                )

                                if let timelineStore = store.scope(
                                    state: \.recordTimeline,
                                    action: \.recordTimeline
                                ) {
                                    let detail = timelineStore.detail
                                    VStack(spacing: LayoutTokens.spacing24) {
                                        ExperimentResultHeaderView(
                                            title: detail.title,
                                            dateRange: ExperimentResultDateFormatter.range(
                                                startedAt: detail.startedAt,
                                                endedAt: detail.endedAt
                                            ),
                                            selectedType: store.selectedType,
                                            selectedSort: store.selectedSort,
                                            onSelectType: {
                                                store.send(.recordFilterSelected($0))
                                            },
                                            onSelectSort: {
                                                store.send(.recordSortSelected($0))
                                            },
                                            onEdit: { store.send(.editTapped) }
                                        )

                                        Separator(orientation: .horizontal)

                                        RecordTimelineView(store: timelineStore)
                                    }
                                }
                            }
                            .scrollBounceBehavior(.basedOnSize)
                            .scrollIndicators(.hidden)
                            .overlay {
                                if let loadMessage = store.loadMessage {
                                    Text(loadMessage)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if store.recordTimeline != nil || store.loadMessage != nil {
                        HStack(spacing: LayoutTokens.spacing16) {
                            if store.recordTimeline != nil {
                                Button {
                                    // 실험 재개 코드 구현
                                } label: {
                                    Text("실험 재개")
                                }
                                .buttonStyle(.labcord(.plain, size: .large))
                            }

                            Button {
                                store.send(.homeTapped)
                            } label: {
                                Text("홈으로 이동")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.labcord(.filled, size: .large))
                        }
                        .padding(.horizontal, LayoutTokens.spacing16)
                        .padding(.top, LayoutTokens.spacing12)
                        .padding(.bottom, max(34 - geometry.safeAreaInsets.bottom, 0))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .navigationBarBackButtonHidden()
                .toolbar(.hidden, for: .navigationBar)
                .task {
                    await store.send(.loadResultDetail).finish()
                }
            }
            .overlay {
                if let overlayStore = store.scope(
                    state: \.titleEditOverlay,
                    action: \.titleEditOverlay
                ) {
                    TitleEditOverlayView(store: overlayStore)
                }
            }
        }
    }
}

#Preview {
    ExperimentResultView(
        store: Store(
            initialState: ExperimentResultFeature.State(experimentID: UUID())
        ) {
            ExperimentResultFeature()
        }
    )
}
