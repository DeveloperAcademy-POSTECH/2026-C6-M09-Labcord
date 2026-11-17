//
//  SortRecordView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/18/26.
//

import ComposableArchitecture
import SwiftUI

struct SortRecordView: View {
    let isPhoneResultReady: Bool
    let onClose: () -> Void
    @State private var store = Store(initialState: SortRecordFeature.State()) {
        SortRecordFeature()
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
                    Text("실험 기록을\n정리중이에요.")
                        .multilineTextAlignment(.center)

                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
        }
        .onAppear {
            if isPhoneResultReady { store.send(.phoneResultReady) }
        }
        .onChange(of: isPhoneResultReady) { _, ready in
            if ready { store.send(.phoneResultReady) }
        }
        .onChange(of: store.shouldClose) { _, shouldClose in
            if shouldClose { onClose() }
        }
        .onDisappear { store.send(.disappeared) }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if store.isPhoneResultReady {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.send(.closeTapped)
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

#Preview {
    SortRecordView(isPhoneResultReady: true, onClose: {})
}
