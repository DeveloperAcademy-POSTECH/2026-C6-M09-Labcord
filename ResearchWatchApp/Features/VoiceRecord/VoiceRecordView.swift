//
//  VoiceRecordView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/17/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import LabcordShared
import LabcordWatchOS
import OSLog
import SwiftUI

private let shortcutLogger = Logger(
    subsystem: "com.researchers.Researchers.watchkitapp", category: "WatchShortcut"
)

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
            case .starting, .awaitingTransfer, .transcribing, .saving:
                VStack(spacing: 4) {
                    Text(progressTitle)

                    ProgressView()
                        .progressViewStyle(.circular)
                        .fixedSize()

                    if store.phase != .starting {
                        if let notice = store.deliveryNotice {
                            Text(notice)
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                        }
                        Button("다시 시도") { store.send(.retryTapped) }
                            .controlSize(.small)
                    }
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
                    Text(store.errorMessage ?? "음성 기록을 진행할 수 없어요.")
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
                Button { store.send(.dismissTapped) } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("닫기")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if store.phase != .saved, store.header != nil {
                    Button("취소", role: .destructive) { store.send(.cancelTapped) }
                }
            }
        }
        .onAppear {
            store.send(.appeared)
            shortcutLogger.info("VoiceRecordView appeared")
            let center = WatchRecordingShortcutCenter.shared
            center.register(.voiceRecording, in: store.experimentID) { shortcut, id in
                stopRecording(for: shortcut, experimentID: id)
            }
        }
        .onDisappear {
            store.send(.disappeared)
            WatchRecordingShortcutCenter.shared.dismissVoice(in: store.experimentID)
            shortcutLogger.info("VoiceRecordView disappeared")
        }
        .onChange(of: store.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
        .task(id: store.phase) {
            let phase = store.phase
            switch phase {
            case .saved:
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                store.send(.dismissTapped)
            case .awaitingTransfer, .transcribing, .saving:
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                store.send(.deliveryDelayed(phase))
            default:
                break
            }
        }
    }

    /// 음성 단축어는 녹음 중일 때만 녹음을 종료하고, 다른 단계에서는 처리하지 않습니다.
    private func stopRecording(
        for shortcut: WatchRecordingShortcut, experimentID: UUID?
    ) -> Bool {
        guard shortcut == .voice else { return false }
        let phase = String(describing: store.phase)
        guard store.phase == .recording,
              experimentID == nil || experimentID == store.experimentID else {
            shortcutLogger.info("Voice stop ignored: phase=\(phase, privacy: .public)")
            return false
        }
        store.send(.finishTapped)
        let next = String(describing: store.phase)
        shortcutLogger.info(
            "Voice stop sent: \(phase, privacy: .public)->\(next, privacy: .public)"
        )
        return true
    }

    private var progressTitle: String {
        switch store.phase {
        case .starting: "마이크 준비 중"
        case .awaitingTransfer:
            store.receivedChunkCount > 0
                ? "iPhone 전송 중 · \(store.receivedChunkCount)개 전송됨"
                : "iPhone 전송 대기 중"
        case .transcribing: "전사 중"
        case .saving: "iPhone 저장 확인 중"
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
