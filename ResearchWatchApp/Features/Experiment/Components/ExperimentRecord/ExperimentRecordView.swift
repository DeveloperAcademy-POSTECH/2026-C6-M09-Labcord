//
//  ExperimentRecordView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/17/26.
//

import LabcordDesignSystem
import LabcordWatchOS
import SwiftUI

struct ExperimentRecordView: View {
    let title: String

    private var buttonHeight: CGFloat {
        WatchScreenMetrics.scaledHeight(45)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchScreenMetrics.scaledHeight(8)) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .frame(
                        height: WatchScreenMetrics.scaledHeight(35),
                        alignment: .topLeading
                    )
                
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: WatchScreenMetrics.scaledHeight(8)
                ) {
                    ExperimentActionButton(systemName: "microphone") { }
                    ExperimentActionButton(systemName: "camera") { }
                    ExperimentActionButton(systemName: "video") { }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, WatchScreenMetrics.scaledHeight(23))
            VStack(spacing: 4) {
                Button("일시정지", systemImage: "pause.fill", action: {})
                    .font(.system(size: 18.5, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: buttonHeight)
                    .buttonStyle(.plain)
                    .background(
                        Color("General/LiveActivity/Secondary"),
                        in: RoundedRectangle(cornerRadius: .infinity)
                    )
                
                Button("종료", systemImage: "stop.fill", action: {})
                    .font(.system(size: 18.5, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: buttonHeight)
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .background(
                        Color(.red).opacity(0.15),
                        in: RoundedRectangle(cornerRadius: .infinity)
                    )
            }
        }
    }
}

#Preview {
    ExperimentRecordView(title: "새 실험(1)")
}
