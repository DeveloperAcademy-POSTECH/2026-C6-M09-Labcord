//
//  SessionHeaderView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct SessionHeaderView: View {
    let store: StoreOf<ExperimentSessionFeature>
    @State private var showsTerms = false

    var body: some View {
        HStack(spacing: 19) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.detail?.title ?? "불러오는 중...")
                    .lineLimit(1)
                    .font(.title2.bold())
                Button("용어 보기") { showsTerms = true }
                    .buttonStyle(.labcord(.accent, size: .small))
                    .disabled(store.detail == nil)
                if store.allowsAudioOnly {
                    Button("카메라 다시 시도") { store.send(.retryCameraRequested) }
                        .buttonStyle(.labcord(.accent, size: .small))
                        .disabled(store.voice.phase != .hidden || store.isCompleting)
                }
            }

            Spacer()

            Button {
                store.send(.stopTapped)
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(!store.canCloseSession)

            Button {
                store.send(.returnHomeTapped)
            } label: {
                Image(systemName: "pause.fill")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(!store.canCloseSession)
        }
        .sheet(isPresented: $showsTerms) {
            SpeechTermsView(terms: store.voice.contextualStrings)
        }
    }
}

#Preview {
    SessionHeaderView(
        store: Store(
            initialState: ExperimentSessionFeature.State(experimentID: UUID())
        ) {
            ExperimentSessionFeature()
        }
    )
}
