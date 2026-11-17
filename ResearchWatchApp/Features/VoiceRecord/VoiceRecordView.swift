//
//  VoiceRecordView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/17/26.
//

import LabcordWatchOS
import SwiftUI

struct VoiceRecordView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: WatchScreenMetrics.scaledHeight(25)) {
            Spacer(minLength: 0)

            VoiceWaveView()

            Button("완료", action: {})
                .frame(maxWidth: .infinity, maxHeight: WatchScreenMetrics.scaledHeight(44))
                .padding(.horizontal, 9.5)
                .padding(.bottom, 9)
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("음성 녹음")
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
    }
}

#Preview {
    VoiceRecordView()
}
