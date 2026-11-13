import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct VoiceToastPresentation: Identifiable {
    enum Kind: Equatable {
        case success
        case recordingFailure
        case photoSaveFailure
        case videoSaveFailure
    }

    let id = UUID()
    let kind: Kind
}

struct VoiceRecordToastOverlay: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let voiceStore: StoreOf<VoiceRecordingFeature>
    let photoStore: StoreOf<PhotoFeature>
    let videoStore: StoreOf<VideoFeature>
    let sessionStore: StoreOf<ExperimentSessionFeature>
    @Binding var presentation: VoiceToastPresentation?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let presentation {
                    toast(for: presentation)
                        .padding(.horizontal, LayoutTokens.spacing16)
                        .safeAreaPadding(
                            .bottom,
                            verticalSizeClass == .compact ? 0 : LayoutTokens.spacing16
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: presentation?.id)
            .onChange(of: voiceStore.phase) { _, phase in
                if phase == .starting {
                    presentation = nil
                }
            }
            .onChange(of: voiceStore.lastSavedRecordID) { _, id in
                if id != nil {
                    presentation = VoiceToastPresentation(kind: .success)
                }
            }
            .onChange(of: photoStore.lastSavedRecordID) { _, id in
                if id != nil {
                    presentation = VoiceToastPresentation(kind: .success)
                }
            }
            .onChange(of: videoStore.lastSavedRecordID) { _, id in
                if id != nil {
                    presentation = VoiceToastPresentation(kind: .success)
                }
            }
            .onChange(of: photoStore.saveError) { _, error in
                if error != nil {
                    presentation = VoiceToastPresentation(kind: .photoSaveFailure)
                } else if presentation?.kind == .photoSaveFailure {
                    presentation = nil
                }
            }
            .onChange(of: videoStore.saveError) { _, error in
                if error != nil {
                    presentation = VoiceToastPresentation(kind: .videoSaveFailure)
                } else if presentation?.kind == .videoSaveFailure {
                    presentation = nil
                }
            }
            .task(id: presentation?.id) {
                guard let current = presentation,
                      current.kind == .success || verticalSizeClass == .compact else { return }
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, presentation?.id == current.id else { return }
                presentation = nil
            }
    }

    @ViewBuilder
    private func toast(for presentation: VoiceToastPresentation) -> some View {
        if presentation.kind == .success {
            Toast(
                "실험 기록을 저장했어요",
                type: .success,
                fillsWidth: verticalSizeClass != .compact
            )
        } else if verticalSizeClass == .compact {
            Toast("실험을 기록하지 못했어요", type: .warning)
        } else {
            Toast(
                "실험을 기록하지 못했어요",
                type: .error,
                fillsWidth: true,
                actionTitle: "다시 시도",
                onAction: { retry(presentation.kind) },
                onDismiss: { dismiss(presentation.kind) }
            )
        }
    }

    private func retry(_ kind: VoiceToastPresentation.Kind) {
        presentation = nil
        switch kind {
        case .success:
            break
        case .recordingFailure:
            sessionStore.send(.voiceStartRequested)
        case .photoSaveFailure:
            photoStore.send(.saveRequested)
        case .videoSaveFailure:
            videoStore.send(.saveRequested)
        }
    }

    private func dismiss(_ kind: VoiceToastPresentation.Kind) {
        presentation = nil
        switch kind {
        case .photoSaveFailure:
            photoStore.send(.saveErrorDismissed)
        case .videoSaveFailure:
            videoStore.send(.saveErrorDismissed)
        case .success, .recordingFailure:
            break
        }
    }
}
