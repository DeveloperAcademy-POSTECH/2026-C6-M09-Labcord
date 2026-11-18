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

/// 프로토콜 모드에서 타이머 목록이 보일 때 툴바로 여는 프리셋 화면입니다.
/// 타이머 탭의 `SettingTimerView`와 같은 모습으로 보이도록 제목·여백을 맞춥니다.
struct SettingTimerScreen: View {
    let timerSeconds: [Int]
    let onStart: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isAddTimerPresented = false

    var body: some View {
        VStack {
            Text("타이머")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color("General/Brand/Primary"))
                .padding(.bottom, WatchScreenMetrics.scaledHeight(4.5))

            SettingTimerView(timerSeconds: timerSeconds) { seconds in
                onStart(seconds)
                dismiss()
            } onAdd: {
                isAddTimerPresented = true
            }
        }
        .padding(.top, WatchScreenMetrics.scaledHeight(24.5))
        .padding(.horizontal, 6)
        .ignoresSafeArea()
        // 타이머 탭에서 + 버튼이 숨겨질 때와 같은 툴바 배치를 유지합니다.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Color.clear
                    .frame(width: 1, height: 1)
            }
        }
        .navigationDestination(isPresented: $isAddTimerPresented) {
            AddTimerView()
        }
    }
}

#Preview {
    SettingTimerView(timerSeconds: [30, 90, 3_600], onStart: { _ in }, onAdd: {})
}

#Preview("프리셋 화면") {
    NavigationStack {
        SettingTimerScreen(timerSeconds: [30, 90, 3_600], onStart: { _ in })
    }
}
