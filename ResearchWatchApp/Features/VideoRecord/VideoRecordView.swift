//
//  VideoRecordView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/17/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import LabcordWatchOS
import SwiftUI

struct VideoRecordView: View {
    let store: StoreOf<VideoRecordFeature>
    @Binding var presentedVideo: StoreOf<VideoRecordFeature>?

    private var retryTitle: String {
        if store.phase == .saveFailed { return "다시 저장" }
        return store.startedAt == nil ? "다시 촬영" : "상태 다시 확인"
    }

    private var waitingTitle: String {
        if store.isStopping { return "녹화 정지 중" }
        return store.isRecovering ? "녹화 상태 확인 중" : "녹화 시작 대기 중"
    }

    var body: some View {
        VStack {
            switch store.phase {
            case .recording:
                Spacer()

                VStack(spacing: WatchScreenMetrics.scaledHeight(4)) {
                    if let start = store.startedAt {
                        Text(store.isStopping ? "녹화 정지 중" : "녹화 중").font(.headline)
                        HStack(alignment: .center, spacing: 2) {
                            Circle()
                                .fill(.red)
                                .frame(
                                    width: WatchScreenMetrics.scaledWidth(9),
                                    height: WatchScreenMetrics.scaledHeight(9)
                                )

                            TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                                let duration = timeline.date.timeIntervalSince(start)
                                let elapsed = min(5, max(0, duration))
                                Text(String(format: "00:%02d", Int(elapsed)))
                                    .font(.system(size: 14))
                                    .monospacedDigit()
                            }
                        }
                    } else {
                        Text(waitingTitle)
                            .font(.headline)
                        ProgressView()
                    }
                }

                Spacer()

                Button {
                    store.send(.stopTapped)
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 21, weight: .semibold))
                }
                .frame(
                    width: WatchScreenMetrics.scaledWidth(40),
                    height: WatchScreenMetrics.scaledHeight(40)
                )
                .disabled(store.recordID == nil || store.isStopping)
                .buttonBorderShape(.circle)

            case .review:
                TranScriptView(
                    transcript: "해당 영상을\n저장할까요?",
                    isSavePrompt: true,
                    autoSaveSeconds: store.autoSaveSeconds,
                    onRerecord: { store.send(.retakeTapped) },
                    onSave: { store.send(.saveTapped) }
                )

            case .saving, .closing:
                VStack(spacing: 4) {
                    Text(store.phase == .saving ? "저장 중" : "처리 중")
                    ProgressView()
                        .progressViewStyle(.circular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .saved:
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color("General/Brand/Primary"))

                    Text("저장 완료")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed, .saveFailed:
                VStack(spacing: 8) {
                    Text(store.failureMessage ?? "영상 촬영에 실패했어요")
                    Button(retryTitle) {
                        store.send(.retryTapped)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(
            [.review, .saved, .closing].contains(store.phase) ? "" : "영상 촬영"
        )
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    store.send(.closeTapped)
                } label: {
                    Image(systemName: "xmark")
                }
                .disabled(store.phase == .saving || store.phase == .closing || store.isStopping)
            }
        }
        .interactiveDismissDisabled(store.phase != .saved)
        .onChange(of: store.shouldDismiss, initial: true) { _, shouldDismiss in
            if shouldDismiss, presentedVideo === store { presentedVideo = nil }
        }
        .task(id: store.phase) {
            guard store.phase == .saved else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, store.phase == .saved else { return }
            store.send(.closeTapped)
        }
    }
}

#Preview {
    let store = Store(initialState: VideoRecordFeature.State(experimentID: UUID())) {
        VideoRecordFeature()
    }
    VideoRecordView(store: store, presentedVideo: .constant(store))
}
