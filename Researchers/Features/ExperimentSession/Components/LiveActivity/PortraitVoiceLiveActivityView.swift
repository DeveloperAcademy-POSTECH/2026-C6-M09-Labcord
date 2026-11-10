import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI
import UIKit

struct PortraitVoiceLiveActivityView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let store: StoreOf<VoiceRecordingFeature>
    let onRestart: () -> Void
    let onFailureAutoDismiss: () -> Void
    let availableWidth: CGFloat
    private static let compactContentHeight: CGFloat = 108

    @State private var isExpanded = false
    @State private var saveProgress = 0.0
    @State private var shouldStartAfterRetry = false

    var body: some View {
        AnimatedLiveActivityContainer(
            isExpanded: isExpanded,
            collapsedSize: CGSize(width: 125, height: 37),
            expandedWidth: max(0, availableWidth - 2 * LayoutTokens.spacing16),
            minimumContentHeight: fixedContentHeight ?? 52,
            maximumContentHeight: dynamicTypeSize.isAccessibilitySize
                ? nil : Self.compactContentHeight,
            animatesContentHeight: store.phase == .finished
        ) {
            LiveActivityContent(
                state: contentState,
                onStop: { store.send(.stopRequested) },
                onRetry: retry
            )
            .animation(nil, value: store.phase)
            .frame(height: fixedContentHeight, alignment: .top)
        }
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

    private var fixedContentHeight: CGFloat? {
        store.phase == .finished && !dynamicTypeSize.isAccessibilitySize
            ? Self.compactContentHeight : nil
    }

    private var contentState: LiveActivityContent.State {
        if store.saveError != nil {
            return .audioError(message: "녹음을 저장하지 못했어요.")
        }
        switch store.phase {
        case .starting:
            return .audioRecording(transcript: "녹음을 준비하고 있어요.")
        case .recording, .stopping:
            return .audioRecording(
                transcript: recentTranscript(
                    store.transcript.isEmpty ? "말씀해 주세요." : store.transcript
                )
            )
        case .finished:
            return .audioResult(
                transcript: recentTranscript(
                    store.transcript.isEmpty ? "녹음된 내용이 없습니다." : store.transcript
                ),
                isSaving: store.isAutoSavePending || store.isSaving,
                progress: saveProgress
            )
        case .hidden:
            return .audioError(message: "녹음하지 못했어요.")
        }
    }

    private func recentTranscript(_ transcript: String) -> String {
        guard !dynamicTypeSize.isAccessibilitySize else { return transcript }

        let font = transcriptFont
        let expandedWidth = max(0, availableWidth - 2 * LayoutTokens.spacing16)
        let textWidth = max(1, expandedWidth - 32 - 24 - 48 - LayoutTokens.spacing12 - 8)
        let measurementInset: CGFloat = 4
        let maximumTextHeight = min(
            4 * font.lineHeight + 4,
            Self.compactContentHeight - titleFont.lineHeight
                - LayoutTokens.spacing10 - measurementInset
        )

        func fits(_ text: String) -> Bool {
            (text as NSString).boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            ).height <= maximumTextHeight
        }

        guard !fits(transcript) else { return transcript }

        let characters = Array(transcript)
        var lowerBound = 0
        var upperBound = characters.count
        while lowerBound < upperBound {
            let count = (lowerBound + upperBound + 1) / 2
            let candidate = "…" + String(characters.suffix(count))
            if fits(candidate) {
                lowerBound = count
            } else {
                upperBound = count - 1
            }
        }
        return "…" + String(characters.suffix(lowerBound))
    }

    private var transcriptFont: UIFont {
        let baseFont = UIFont(name: "PretendardVariable-Regular", size: 15)
            ?? UIFont.preferredFont(forTextStyle: .subheadline)
        return UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: baseFont)
    }

    private var titleFont: UIFont {
        let baseFont = UIFont(name: "PretendardVariable-Regular", size: 13)
            ?? UIFont.preferredFont(forTextStyle: .footnote)
        return UIFontMetrics(forTextStyle: .footnote).scaledFont(for: baseFont)
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
