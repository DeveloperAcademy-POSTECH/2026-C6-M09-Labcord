//
//  SessionTimerView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import LabcordShared
import SwiftUI

struct SessionTimerView: View {
    let store: StoreOf<ExperimentSessionFeature>
    @State private var selectedPage: Int? = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 20) {
                    Button {
                        store.send(.timerTabSelected(.configured))
                    } label: {
                        Text("세팅된 타이머")
                            .foregroundStyle(
                                store.selectedTimerTab == .active
                                ? Color.gray
                                : Color.white
                            )
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        store.send(.timerTabSelected(.active))
                    } label: {
                        HStack(spacing: 8) {
                            Text("진행중인 타이머")
                                .foregroundStyle(
                                    store.selectedTimerTab == .active
                                    ? Color.white
                                    : Color.gray
                                )
                                .font(.body.weight(.semibold))
                            
                            Text("3")
                                .foregroundStyle(.orange)
                                .font(.body.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Button {
                    
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.blue)
                }
            }
            
            if store.selectedTimerTab == .active || store.timerSeconds.isEmpty {
                Rectangle()
                    .foregroundStyle(.gray.opacity(0.2))
                    .frame(height: 91)
                    .cornerRadius(6)
                    .overlay {
                        Text(
                            store.selectedTimerTab == .active
                            ? "진행 중인 타이머가 없어요"
                            : "설정된 타이머가 없어요"
                        )
                        .foregroundStyle(.gray)
                        .font(.footnote)
                    }
            } else {
                let tileWidth: CGFloat = 91
                let tileHeight: CGFloat = 58.67
                let tileSpacing: CGFloat = 12
                let gridHeight = tileHeight * 3 + tileSpacing * 2

                GeometryReader { geometry in
                    let threeColumnWidth = tileWidth * 3 + tileSpacing * 2
                    let columnCount = geometry.size.width >= threeColumnWidth ? 3 : 2
                    let itemsPerPage = columnCount * 3
                    let pageCount = (store.timerSeconds.count + itemsPerPage - 1) / itemsPerPage
                    let currentPage = min(selectedPage ?? 0, pageCount - 1)

                    VStack(spacing: 8) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 0) {
                                ForEach(0..<pageCount, id: \.self) { page in
                                    let start = page * itemsPerPage
                                    let end = min(start + itemsPerPage, store.timerSeconds.count)

                                    LazyVGrid(
                                        columns: Array(
                                            repeating: GridItem(.fixed(tileWidth), spacing: tileSpacing),
                                            count: columnCount
                                        ),
                                        alignment: .leading,
                                        spacing: tileSpacing
                                    ) {
                                        ForEach(start..<end, id: \.self) { index in
                                            Text(TimerDurationFormatter.string(from: store.timerSeconds[index]))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.8)
                                                .frame(width: tileWidth, height: tileHeight)
                                                .background(.gray.opacity(0.3))
                                                .cornerRadius(6)
                                        }
                                    }
                                    .frame(width: geometry.size.width, height: gridHeight, alignment: .topLeading)
                                    .id(page)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollIndicators(.hidden)
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: $selectedPage)
                        .clipped()
                        .frame(height: gridHeight)

                        HStack(spacing: 6) {
                            ForEach(0..<pageCount, id: \.self) { page in
                                Circle()
                                    .fill(currentPage == page ? Color.white : Color.gray)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                    .onChange(of: pageCount) { _, newCount in
                        if let selectedPage, selectedPage >= newCount {
                            self.selectedPage = max(newCount - 1, 0)
                        }
                    }
                }
                .frame(height: gridHeight + 10)
            }
        }
    }
}

#Preview {
    SessionTimerView(store: Store(initialState: ExperimentSessionFeature.State()) {
        ExperimentSessionFeature()
    })
}
