import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct VoiceToastPresentation: Identifiable {
    enum Kind {
        case success
        case recordingFailure
        case saveFailure
    }

    let id = UUID()
    let kind: Kind
}

struct VoiceRecordToastOverlay: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let voiceStore: StoreOf<VoiceRecordingFeature>
    let sessionStore: StoreOf<ExperimentSessionFeature>
    @Binding var presentation: VoiceToastPresentation?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let presentation, verticalSizeClass != .compact {
                    toast(for: presentation)
                        .padding(.horizontal, LayoutTokens.spacing16)
                        .padding(.bottom, LayoutTokens.spacing16)
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
                if id != nil, verticalSizeClass != .compact {
                    presentation = VoiceToastPresentation(kind: .success)
                }
            }
            .onChange(of: voiceStore.saveError) { _, error in
                if error != nil, verticalSizeClass != .compact {
                    presentation = VoiceToastPresentation(kind: .saveFailure)
                }
            }
            .task(id: presentation?.id) {
                guard let current = presentation, current.kind == .success else { return }
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, presentation?.id == current.id else { return }
                presentation = nil
            }
    }

    @ViewBuilder
    private func toast(for presentation: VoiceToastPresentation) -> some View {
        if presentation.kind == .success {
            Toast("실험 기록을 저장했어요", type: .success, fillsWidth: true)
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
        case .saveFailure:
            voiceStore.send(.saveRequested)
        }
    }

    private func dismiss(_ kind: VoiceToastPresentation.Kind) {
        presentation = nil
        if kind == .saveFailure {
            voiceStore.send(.closeRequested)
        }
    }
}
