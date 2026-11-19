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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let store: StoreOf<VoiceRecordFeature>
    @Binding var presentedRecording: StoreOf<VoiceRecordFeature>?

    private var isPresented: Bool { presentedRecording === store }

    var body: some View {
        VStack(spacing: WatchScreenMetrics.scaledHeight(25)) {
            switch store.phase {
            case .checkingPending, .starting, .awaitingTransfer, .transcribing, .saving:
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

                Button("완료") { store.send(.finishRequested(playsFeedback: true)) }
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
                    if store.header != nil {
                        Button("새로 녹음") { store.send(.rerecordTapped) }
                    }
                    Button(store.header == nil ? "다시 시도" : "이전 기록 재시도") {
                        store.send(.retryTapped)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.phase == .recording
        )
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
            guard isPresented else { return }
            shortcutLogger.info("VoiceRecordView appeared")
            let center = WatchRecordingShortcutCenter.shared
            center.register(.voiceRecording, in: store.experimentID) { shortcut, id in
                stopRecording(for: shortcut, experimentID: id)
            }
        }
        .onChange(of: store.shouldDismiss, initial: true) { _, shouldDismiss in
            if shouldDismiss, isPresented { presentedRecording = nil }
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

    private func stopRecording(
        for shortcut: WatchRecordingShortcut, experimentID: UUID?
    ) -> Bool {
        guard isPresented, shortcut == .voice,
              experimentID == nil || experimentID == store.experimentID
        else { return false }
        let phase = String(describing: store.phase)
        guard store.phase == .recording else {
            shortcutLogger.info("Voice shortcut already handled: phase=\(phase, privacy: .public)")
            return store.phase != .failed
        }
        store.send(.finishRequested(playsFeedback: false))
        let next = String(describing: store.phase)
        shortcutLogger.info(
            "Voice stop sent: \(phase, privacy: .public)->\(next, privacy: .public)"
        )
        return true
    }

    private var progressTitle: String {
        switch store.phase {
        case .checkingPending: "이전 음성 기록 확인 중"
        case .starting: "마이크 준비 중"
        case .awaitingTransfer:
            if let size = store.transferSize {
                "iPhone 전송 \(size.percentage(for: store.latestReceipt?.receivedSequences ?? []))%"
            } else {
                "iPhone 전송 대기 중"
            }
        case .transcribing: "전사 중"
        case .saving: "iPhone 저장 확인 중"
        default: ""
        }
    }

    private var navigationTitle: String {
        [.checkingPending, .transcript, .saved].contains(store.phase) ? "" : "음성 녹음"
    }
}

#Preview {
    let store = Store(initialState: VoiceRecordFeature.State(experimentID: UUID())) {
        VoiceRecordFeature()
    }
    VoiceRecordView(store: store, presentedRecording: .constant(store))
}
