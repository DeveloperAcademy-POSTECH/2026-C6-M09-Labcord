//
//  VoiceRecordView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/17/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import LabcordWatchOS
import SwiftUI

struct VoiceRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store: StoreOf<VoiceRecordFeature>

    init(experimentID: UUID) {
        _store = State(initialValue: Store(
            initialState: VoiceRecordFeature.State(experimentID: experimentID)
        ) {
            VoiceRecordFeature()
        })
    }

    var body: some View {
        VStack(spacing: WatchScreenMetrics.scaledHeight(25)) {
            switch store.phase {
            case .starting, .transcribing, .saving:
                VStack(spacing: 4) {
                    Text(progressTitle)

                    ProgressView()
                        .progressViewStyle(.circular)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .recording:
                Spacer(minLength: 0)

                VoiceWaveView(isVoiceDetected: store.isVoiceDetected)

                Button("완료") { store.send(.finishTapped) }
                    .frame(maxWidth: .infinity, maxHeight: WatchScreenMetrics.scaledHeight(44))
                    .padding(.horizontal, 9.5)
                    .padding(.bottom, 9)

            case .transcript:
                TranScriptView(
                    transcript: store.transcript,
                    isSavePrompt: false,
                    autoSaveSeconds: store.autoSaveSeconds,
                    onRerecord: { store.send(.rerecordTapped) },
                    onSave: { store.send(.saveTapped) }
                )

            case .saved:
                VStack(alignment: .center, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color("General/Brand/Primary"))

                    Text("저장 완료")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed:
                VStack(spacing: 12) {
                    Text("음성 기록을 진행할 수 없어요.")
                    Button("다시 시도") { store.send(.retryTapped) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if store.phase == .saved {
                        dismiss()
                    } else {
                        store.send(.cancelTapped)
                    }
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .interactiveDismissDisabled(store.phase != .saved)
        .onAppear { store.send(.appeared) }
        .onDisappear { store.send(.disappeared) }
        .onChange(of: store.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
        .task(id: store.phase) {
            guard store.phase == .saved else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, store.phase == .saved else { return }
            dismiss()
        }
    }

    private var progressTitle: String {
        switch store.phase {
        case .starting: "마이크 준비 중"
        case .transcribing: "전사 중"
        case .saving: "저장 중"
        default: ""
        }
    }

    private var navigationTitle: String {
        store.phase == .transcript || store.phase == .saved ? "" : "음성 녹음"
    }
}

#Preview {
    VoiceRecordView(experimentID: UUID())
}
