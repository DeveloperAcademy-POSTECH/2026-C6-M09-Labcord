//
//  SettingTimerView.swift
//  ResearchWatch Watch App
//
//  Created by 정홍섭 on 11/17/26.
//

import SwiftUI
import LabcordWatchOS
import LabcordDesignSystem

struct SettingTimerView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("진행 중인 타이머")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(
                        height: WatchScreenMetrics.scaledHeight(16),
                        alignment: .topLeading
                    )
                    .padding(.horizontal, 9.5)
                    .padding(.bottom, WatchScreenMetrics.scaledHeight(10))

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: WatchScreenMetrics.scaledHeight(6)
                ) {
                    Button {
                        // 구현 예정
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 28))
                            .frame(
                                width: WatchScreenMetrics.scaledHeight(68),
                                height: WatchScreenMetrics.scaledHeight(68)
                            )
                    }
                    .buttonBorderShape(.circle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

#Preview {
    SettingTimerView()
}
