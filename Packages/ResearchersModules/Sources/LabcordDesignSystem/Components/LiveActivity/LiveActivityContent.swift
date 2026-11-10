import SwiftUI

public struct LiveActivityContent: View {
    public enum State: Sendable {
        case audioRecording(transcript: String)
        case videoRecording(elapsed: String, progress: Double)
        case audioError(message: String)
        case audioResult(transcript: String, isSaving: Bool, progress: Double)
        case watchConnected(message: String, detail: String)
    }

    private let state: State
    private let isVideoStopComplete: Bool
    private let onStop: () -> Void
    private let onRetry: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        state: State,
        isVideoStopComplete: Bool = false,
        onStop: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.state = state
        self.isVideoStopComplete = isVideoStopComplete
        self.onStop = onStop
        self.onRetry = onRetry
    }

    public var body: some View {
        HStack(alignment: contentAlignment, spacing: LayoutTokens.spacing12) {
            leading
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
    }

    private var contentAlignment: VerticalAlignment {
        switch state {
        case .audioRecording, .audioResult:
            return .top
        default:
            return .center
        }
    }

    private func resultControls(isSaving: Bool, progress: Double) -> some View {
        VStack(spacing: LayoutTokens.spacing10) {
            LiveActivityStatusIndicator(
                status: isSaving ? .audioSaving : .audioSaved,
                progress: progress
            )
            LiveActivityControlButton(kind: .retry, action: onRetry)
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch state {
        case let .audioRecording(transcript):
            textGroup(
                title: "녹음 중",
                message: transcript,
                style: Typography.subheadline,
                lines: 4,
                truncationMode: .head
            )
        case let .videoRecording(elapsed, _):
            VStack(alignment: .leading, spacing: LayoutTokens.spacing2) {
                HStack(spacing: 0) {
                    IconArtwork(icon: .dot, size: 22)
                    Text(elapsed).typography(Typography.body)
                }
                .foregroundStyle(Color(.General.Recording.Active.color))
                Text("영상 녹화 중")
                    .typography(Typography.title3)
                    .foregroundStyle(Color(.General.Label.light))
            }
        case let .audioError(message):
            textGroup(title: "녹음 결과", message: message, style: Typography.title3, lines: 1)
        case let .audioResult(transcript, _, _):
            textGroup(
                title: "녹음 결과",
                message: transcript,
                style: Typography.subheadline,
                lines: 4,
                truncationMode: .head
            )
        case let .watchConnected(message, detail):
            VStack(alignment: .leading, spacing: LayoutTokens.spacing10) {
                Text("연결 완료")
                    .typography(Typography.footnote)
                    .foregroundStyle(Color(.General.Label.brand))
                VStack(alignment: .leading, spacing: 0) {
                    Text(message)
                        .typography(Typography.callout)
                        .foregroundStyle(Color(.General.Label.light))
                    Text(detail)
                        .typography(Typography.footnote)
                        .foregroundStyle(Color(.General.Label.tertiary))
                }
            }
        }
    }

    private func textGroup(
        title: String,
        message: String,
        style: TypographyStyle,
        lines: Int,
        truncationMode: Text.TruncationMode = .tail
    ) -> some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing10) {
            Text(title)
                .typography(Typography.footnote)
                .foregroundStyle(Color(.General.Label.brand))
            Text(message)
                .typography(style)
                .foregroundStyle(Color(.General.Label.light))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : lines)
                .truncationMode(truncationMode)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .audioRecording:
            LiveActivityControlButton(kind: .audioStop, action: onStop)
        case let .videoRecording(_, progress):
            LiveActivityControlButton(
                kind: isVideoStopComplete ? .videoStopComplete : .videoStopInProgress,
                progress: progress,
                action: onStop
            )
        case .audioError:
            LiveActivityControlButton(kind: .retry, action: onRetry)
        case let .audioResult(_, isSaving, progress):
            resultControls(isSaving: isSaving, progress: progress)
        case .watchConnected:
            LiveActivityStatusIndicator(status: .watchConnected)
        }
    }
}

#Preview("Live Activity Content") {
    VStack(spacing: 12) {
        LiveActivityContainer {
            LiveActivityContent(state: .audioRecording(transcript: "실험 내용을 기록하고 있어요."),
                                onStop: {}, onRetry: {})
        }
        LiveActivityContainer {
            LiveActivityContent(state: .videoRecording(elapsed: "00:05", progress: 0.6),
                                onStop: {}, onRetry: {})
        }
        LiveActivityContainer {
            LiveActivityContent(
                state: .audioError(message: "인식된 음성이 없습니다."), onStop: {}, onRetry: {}
            )
        }
    }
    .padding()
}
