//
//  StopExperimentView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/18/26.
//

import LabcordDesignSystem
import LabcordWatchOS
import SwiftUI

struct StopExperimentView: View {
    let onStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(
                alignment: .center,
                spacing: WatchScreenMetrics.scaledHeight(8)
            ) {
                Spacer()

                Text("실험 일시정지")
                    .font(.headline)

                Text("지금까지 기록한 내용은\n저장돼요.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(height: WatchScreenMetrics.scaledHeight(33))

                VStack(
                    alignment: .center,
                    spacing: WatchScreenMetrics.scaledHeight(4)
                ) {
                    Button(action: onStop) {
                        Text("기록 중단")
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: WatchScreenMetrics.scaledHeight(45))
                            .background(
                                Color("General/Brand/Primary"),
                                in: RoundedRectangle(cornerRadius: .infinity)
                            )
                    }
                    .buttonStyle(PressFeedbackButtonStyle())

                    Button("취소", action: onCancel)
                        .frame(height: WatchScreenMetrics.scaledHeight(45))
                }
            }
        }
        .padding(.horizontal, 9.5)
        .background(.black)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
            }
        }
    }
}

#Preview {
    StopExperimentView(onStop: {}, onCancel: {})
}
