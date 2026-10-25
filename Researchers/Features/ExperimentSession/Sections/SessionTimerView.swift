//
//  SessionTimerView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import SwiftUI

struct SessionTimerView: View {
    let store: StoreOf<ExperimentSessionFeature>

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 20) {
                    Button {
                        store.send(.timerTabSelected(.configured))
                    } label: {
                        Text("세팅된 타이머")
                            .foregroundStyle(store.selectedTimerTab == .active ? Color.gray : Color.white)
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.send(.timerTabSelected(.active))
                    } label: {
                        HStack(spacing: 8) {
                            Text("진행중인 타이머")
                                .foregroundStyle(store.selectedTimerTab == .active ? Color.white : Color.gray)
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

            Rectangle()
                .foregroundStyle(.gray.opacity(0.2))
                .frame(height: 91)
                .cornerRadius(6)
                .overlay {
                    Text(store.selectedTimerTab == .active ? "진행 중인 타이머가 없어요" : "설정된 타이머가 없어요")
                        .foregroundStyle(.gray)
                        .font(.footnote)
                }
        }
    }
}

#Preview {
    SessionTimerView(store: Store(initialState: ExperimentSessionFeature.State()) {
        ExperimentSessionFeature()
    })
}
