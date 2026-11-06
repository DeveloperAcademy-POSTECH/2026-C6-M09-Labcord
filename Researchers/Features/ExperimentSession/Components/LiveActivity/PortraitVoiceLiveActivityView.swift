import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct PortraitVoiceLiveActivityView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let store: StoreOf<VoiceRecordingFeature>
    let onRestart: () -> Void
    let onFailureAutoDismiss: () -> Void
    let availableWidth: CGFloat

    @State private var isExpanded = false
    @State private var saveProgress = 0.0
    @State private var shouldStartAfterRetry = false

    var body: some View {
        AnimatedLiveActivityContainer(
            isExpanded: isExpanded,
            collapsedSize: CGSize(width: 125, height: 37),
            expandedWidth: max(0, availableWidth - 2 * LayoutTokens.spacing16),
            minimumContentHeight: 52,
            maximumContentHeight: dynamicTypeSize.isAccessibilitySize ? nil : 106
        ) {
            LiveActivityContent(
                state: contentState,
                onStop: { store.send(.stopRequested) },
                onRetry: retry
            )
        }
        .animation(
            reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.08),
            value: store.phase
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: store.transcript)
        .task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            isExpanded = true
        }
        .onAppear {
            store.send(.overlayAppeared)
            if store.phase == .finished {
                startSaveProgress()
            }
        }
        .onChange(of: store.phase) { _, phase in
            if phase == .finished {
                startSaveProgress()
            } else if phase == .starting, shouldStartAfterRetry {
                shouldStartAfterRetry = false
                store.send(.overlayAppeared)
            }
        }
        .task(id: store.hasRecordingFailure) {
            guard store.hasRecordingFailure else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, store.hasRecordingFailure else { return }
            store.send(.errorDismissed)
            onFailureAutoDismiss()
        }
    }

    private var contentState: LiveActivityContent.State {
        if store.saveError != nil {
            return .audioError(message: "녹음을 저장하지 못했어요.")
        }
        if store.phase == .hidden {
            return .audioError(message: "녹음하지 못했어요.")
        }

        switch store.phase {
        case .starting:
            return .audioRecording(transcript: "녹음을 준비하고 있어요.")
        case .recording, .stopping:
            return .audioRecording(
                transcript: store.transcript.isEmpty ? "말씀해 주세요." : store.transcript
            )
        case .finished:
            return .audioResult(
                transcript: store.transcript.isEmpty ? "녹음된 내용이 없습니다." : store.transcript,
                isSaving: store.isAutoSavePending || store.isSaving,
                progress: saveProgress
            )
        case .hidden:
            return .audioError(message: "녹음하지 못했어요.")
        }
    }

    private func retry() {
        if store.saveError != nil {
            store.send(.saveRequested)
        } else if store.phase == .finished {
            store.send(.retakeRequested)
        } else {
            shouldStartAfterRetry = true
            store.send(.errorDismissed)
            onRestart()
        }
    }

    private func startSaveProgress() {
        saveProgress = 0
        withAnimation(.linear(duration: 3)) {
            saveProgress = 1
        }
    }
}
