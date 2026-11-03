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
                        ScrollView {
                            NavigationPageTitle(
                                "실험 기록",
                                onBack: store.isOpenedFromHome ? { store.send(.homeTapped) } : nil
                            )

                            if let detail = store.detail {
                                VStack(spacing: LayoutTokens.spacing24) {
                                    ExperimentResultHeaderView(
                                        title: detail.title,
                                        dateRange: ExperimentResultDateFormatter.range(
                                            startedAt: detail.startedAt,
                                            endedAt: detail.endedAt
                                        ),
                                        selectedType: store.selectedType,
                                        selectedSort: store.selectedSort,
                                        onSelectType: { store.send(.recordFilterSelected($0)) },
                                        onSelectSort: { store.send(.recordSortSelected($0)) },
                                        onEdit: { store.send(.editTapped) }
                                    )

                                    Separator(orientation: .horizontal)

                                    VStack(alignment: .leading) {
                                        Text(ExperimentResultDateFormatter.date(detail.createdAt))
                                    }
                                    .padding(.horizontal, LayoutTokens.spacing16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollIndicators(.hidden)
                        .overlay {
                            if store.detail == nil {
                                if let loadMessage = store.loadMessage {
                                    Text(loadMessage)
                                } else {
                                    ExperimentProcessingView()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    HStack(spacing: LayoutTokens.spacing16) {
                        if store.detail != nil {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationBarBackButtonHidden()
                .toolbar(.hidden, for: .navigationBar)
                .task {
                    await store.send(.loadResultDetail).finish()
                }
            }
            .overlay {
                if store.isTitleEditPresented, let title = store.detail?.title {
                    TitleEditOverlayView(originalTitle: title) {
                        store.send(.titleEditDismissed)
                    }
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
