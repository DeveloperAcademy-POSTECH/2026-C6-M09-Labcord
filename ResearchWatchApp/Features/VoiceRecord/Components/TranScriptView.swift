//
//  TranScriptView.swift
//  ResearchWatch Watch App
//
//  Created by 정홍섭 on 11/17/26.
//

import LabcordDesignSystem
import LabcordWatchOS
import SwiftUI

struct TranScriptView: View {
    let transcript: String
    let autoSaveSeconds: Int
    let onRerecord: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack {
            ScrollView {
                Text(transcript)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)

                Text("\(autoSaveSeconds)초 후 자동 저장돼요")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 10)

            HStack {
                Button(action: onRerecord) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15.68354, weight: .semibold))
                }
                .frame(
                    width: WatchScreenMetrics.scaledWidth(29.87342),
                    height: WatchScreenMetrics.scaledWidth(29.87342)
                )
                .buttonBorderShape(.circle)

                Spacer()

                Button(action: onSave) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15.68354, weight: .semibold))
                        .frame(
                            width: WatchScreenMetrics.scaledWidth(29.87342),
                            height: WatchScreenMetrics.scaledWidth(29.87342)
                        )
                        .background(
                            Color("General/Brand/Primary"),
                            in: Circle()
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 9.5)
        }
    }
}

#Preview {
    TranScriptView(
        transcript: "전사전사", autoSaveSeconds: 3,
        onRerecord: {}, onSave: {}
    )
}
