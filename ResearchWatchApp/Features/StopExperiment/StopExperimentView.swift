//
//  StopExperimentView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/18/26.
//

import SwiftUI
import LabcordWatchOS
import LabcordDesignSystem

struct StopExperimentView: View {
    var body: some View {
        ScrollView {
            VStack(
                alignment: .center,
                spacing: WatchScreenMetrics.scaledHeight(8)
            ) {
                Spacer()
                
                Text("실험 중단")
                    .font(.headline)
                
                Text("지금 기록 중인 내용은\n저장되지 않아요.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(height: WatchScreenMetrics.scaledHeight(33))
                
                VStack(
                    alignment: .center,
                    spacing: WatchScreenMetrics.scaledHeight(4)
                ) {
                    Button {} label: {
                        Text("기록 중단")
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: WatchScreenMetrics.scaledHeight(45))
                            .background(
                                Color("General/Brand/Primary"),
                                in: RoundedRectangle(cornerRadius: .infinity)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    Button("취소", action: {})
                        .frame(height: WatchScreenMetrics.scaledHeight(45))
                }
            }
        }
        .padding(.horizontal, 9.5)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
    }
}

#Preview {
    StopExperimentView()
}
