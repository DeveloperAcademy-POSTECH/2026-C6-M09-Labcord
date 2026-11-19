//
//  SortRecordView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/18/26.
//

import ComposableArchitecture
import Foundation
import LabcordShared
import SwiftUI

struct SortRecordView: View {
    let isPhoneResultReady: Bool
    let onClose: () -> Void
    @State private var store: StoreOf<SortRecordFeature>

    init(
        experimentID: UUID, isPhoneResultReady: Bool,
        sendCommand: @escaping SortRecordFeature.SendCommand, onClose: @escaping () -> Void
    ) {
        self.isPhoneResultReady = isPhoneResultReady
        self.onClose = onClose
        _store = State(initialValue: Store(initialState: .init(experimentID: experimentID)) {
            SortRecordFeature(sendCommand: sendCommand)
        })
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if store.isPhoneResultReady {
                ScrollView {
                    VStack(spacing: 13) {
                        Spacer()

                        VStack(spacing: 8) {
                            Image(systemName: "iphone")
                                .foregroundStyle(.white)
                                .font(.largeTitle)

                            Text("iPhone에서\n기록을 확인하세요.")
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                        }

                        Button("확인") { store.send(.closeTapped) }
                    }
                }
                .padding(.horizontal, 9.5)
                .padding(.bottom, 10)
            } else {
                VStack(alignment: .center, spacing: 8) {
                    Text(store.feedback ?? "iPhone 결과 화면을 기다리고 있어요.")
                        .multilineTextAlignment(.center)

                    if store.isQuerying {
                        ProgressView()
                    } else {
                        Button("다시 확인") { store.send(.requeryTapped) }
                    }
                }
                .padding(.horizontal, 9.5)
            }
        }
        .onChange(of: isPhoneResultReady, initial: true) { _, ready in
            store.send(.phoneResultChanged(ready))
        }
        .onChange(of: store.shouldClose) { _, shouldClose in
            if shouldClose { onClose() }
        }
        .onDisappear { store.send(.disappeared) }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    store.send(.closeTapped)
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("닫기")
            }
        }
    }
}

#Preview {
    SortRecordView(
        experimentID: UUID(), isPhoneResultReady: true,
        sendCommand: { .init(requestID: $0.requestID, phase: .completed) },
        onClose: {}
    )
}
