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
    @Environment(\.dismiss) private var dismiss
    @State private var store: StoreOf<VideoRecordFeature>

    init(experimentID: UUID) {
        _store = State(initialValue: Store(
            initialState: VideoRecordFeature.State(experimentID: experimentID)
        ) {
            VideoRecordFeature()
        })
    }

    var body: some View {
        VStack {
            switch store.phase {
            case .recording:
                Spacer()

                VStack(spacing: WatchScreenMetrics.scaledHeight(4)) {
                    Text("녹화 중")
                        .font(.headline)
                    HStack(alignment: .center, spacing: 2) {
                        Circle()
                            .fill(.red)
                            .frame(
                                width: WatchScreenMetrics.scaledWidth(9),
                                height: WatchScreenMetrics.scaledHeight(9)
                            )

                        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                            let elapsed = store.startedAt.map {
                                min(5, max(0, timeline.date.timeIntervalSince($0)))
                            } ?? 0
                            Text(String(format: "00:%02d", Int(elapsed)))
                                .font(.system(size: 14))
                                .monospacedDigit()
                        }
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
                .disabled(store.startedAt == nil || store.isStopping)
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

            case .failed:
                VStack(spacing: 8) {
                    Text("영상 촬영에 실패했어요")
                    Button("다시 시도") { store.send(.start(UUID())) }
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
                    if store.phase == .saved { dismiss() } else { store.send(.closeTapped) }
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
}

#Preview {
    VideoRecordView(experimentID: UUID())
}
