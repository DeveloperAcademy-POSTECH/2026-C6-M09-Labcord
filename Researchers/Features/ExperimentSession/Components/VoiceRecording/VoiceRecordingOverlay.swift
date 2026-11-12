//
//  VoiceRecordingOverlay.swift
//  Researchers
//
//  Created by 정홍섭 on 11/13/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct VoiceRecordingOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let store: StoreOf<VoiceRecordingFeature>

    @State private var isSpeaking = false

    private var microphoneColor: Color {
        Color("Experiment/Action/Primary/Background")
    }

    private var showsFailure: Bool {
        store.hasRecordingFailure || store.saveError != nil
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width * 710 / 874
            let transcriptHeight = geometry.size.height * 178 / 402
            let verticalInset = geometry.size.height * 42 / 402

            ZStack {
                VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
                    .ignoresSafeArea()

                Color("General/Overlay/Scrim")
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    header

                    if showsFailure {
                        failureMessage
                            .padding(.top, 24)
                    } else {
                        Text(store.transcript)
                            .typography(Typography.title1)
                            .foregroundStyle(Color("Experiment/Label/Primary"))
                            .lineLimit(5)
                            .truncationMode(.head)
                            .frame(
                                width: contentWidth,
                                height: transcriptHeight,
                                alignment: .topLeading
                            )
                    }
                }
                .padding(.top, verticalInset)
                .frame(width: contentWidth, height: geometry.size.height, alignment: .top)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    if store.phase == .finished && !showsFailure {
                        reviewControls
                    } else {
                        microphoneButton
                            .frame(maxWidth: .infinity)
                            .frame(height: 70)
                    }
                }
                .padding(.bottom, verticalInset)
                .frame(width: contentWidth, height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .onChange(of: store.phase, initial: true) { _, phase in
            if phase == .starting { store.send(.overlayAppeared) }
        }
        .task(id: store.transcript) {
            guard store.phase == .recording, !store.transcript.isEmpty else {
                isSpeaking = false
                return
            }
            isSpeaking = true
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            isSpeaking = false
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                store.send(.closeRequested)
            } label: {
                Image(labcordIcon: .x)
            }
            .buttonStyle(.labcordIcon(.plain, size: .large, colorPalette: .experiment))

            Text("음성 기록")
                .typography(Typography.headline)
                .foregroundStyle(.white)

            Spacer()
        }
    }

    private var failureMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("녹음하지 못했어요.")
                .typography(Typography.title1)
                .foregroundStyle(Color("Experiment/Label/Primary",))

            Text("하단 마이크 버튼을 눌러 다시 녹음해 주세요.")
                .typography(Typography.title3)
                .foregroundStyle(Color("Experiment/Label/Secondary",))
        }
    }

    private var microphoneButton: some View {
        ZStack {
            if isSpeaking && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    ZStack {
                        ForEach(0..<3) { index in
                            let progress = (
                                context.date.timeIntervalSinceReferenceDate
                                    + Double(index) * 0.4
                            ).truncatingRemainder(dividingBy: 1.2) / 1.2

                            Circle()
                                .fill(microphoneColor.opacity(0.32 * (1 - progress)))
                                .frame(width: 70, height: 70)
                                .scaleEffect(1 + progress * 0.9)
                        }
                    }
                }
                .allowsHitTesting(false)
            }

            Button {
                if store.phase == .finished {
                    store.send(.retakeRequested)
                } else if store.phase == .hidden {
                    store.send(.prepareRequested)
                } else {
                    store.send(.stopRequested)
                }
            } label: {
                Image(labcordIcon: .microphoneFill)
            }
            .buttonStyle(.labcordIcon(.filled, size: .extraLarge, colorPalette: .experiment))
            .disabled(store.phase == .stopping || store.phase == .starting)
        }
        .frame(width: 140, height: 140)
    }

    private var reviewControls: some View {
        ExperimentReviewActions(
            retakeLabel: "다시 녹음",
            isSaving: store.isSaving,
            showsAutoSaveNotice: store.isAutoSavePending,
            onRetake: { store.send(.retakeRequested) },
            onSave: { store.send(.saveRequested) }
        )
    }
}
