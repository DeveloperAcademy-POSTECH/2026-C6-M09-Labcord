//
//  SettingTimerView.swift
//  ResearchWatch Watch App
//
//  Created by 정홍섭 on 11/17/26.
//

import LabcordDesignSystem
import LabcordWatchOS
import SwiftUI

struct SettingTimerView: View {
    let timerSeconds: [Int]
    let onStart: (Int) -> Void
    let onAdd: () -> Void

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
                    ForEach(timerSeconds.indices, id: \.self) { index in
                        SettingTimerItemView(seconds: timerSeconds[index]) {
                            onStart(timerSeconds[index])
                        }
                    }

                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 28))
                            .frame(
                                width: WatchScreenMetrics.scaledHeight(68),
                                height: WatchScreenMetrics.scaledHeight(68)
                            )
                    }
                    .buttonBorderShape(.circle)
                    .padding(.vertical, -WatchScreenMetrics.scaledHeight(4))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

struct SettingTimerScreen: View {
    let timerSeconds: [Int]
    let canAddTimer: Bool
    let onStart: (Int) -> Void
    let onCustomStart: (Int) -> Void
    @State private var isAddTimerPresented = false

    var body: some View {
        VStack {
            Text("타이머")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color("General/Brand/Primary"))
                .padding(.bottom, WatchScreenMetrics.scaledHeight(4.5))

            SettingTimerView(timerSeconds: timerSeconds, onStart: onStart) {
                isAddTimerPresented = true
            }
        }
        .padding(.top, WatchScreenMetrics.scaledHeight(24.5))
        .padding(.horizontal, 6)
        .ignoresSafeArea()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Color.clear
                    .frame(width: 1, height: 1)
            }
        }
        .navigationDestination(isPresented: $isAddTimerPresented) {
            AddTimerView(canAddTimer: canAddTimer, onStart: onCustomStart)
        }
    }
}

#Preview {
    SettingTimerView(timerSeconds: [30, 90, 3_600], onStart: { _ in }, onAdd: {})
}

#Preview("프리셋 화면") {
    NavigationStack {
        SettingTimerScreen(
            timerSeconds: [30, 90, 3_600], canAddTimer: true,
            onStart: { _ in }, onCustomStart: { _ in }
        )
    }
}
