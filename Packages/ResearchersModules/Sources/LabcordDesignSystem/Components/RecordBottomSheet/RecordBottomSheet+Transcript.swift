import SwiftUI

#if os(watchOS)
@MainActor
func recordSheetReadOnlyText(_ text: String) -> some View {
    Text(text.isEmpty ? "내용을 입력해 주세요" : text)
        .typography(Typography.subheadline)
        .foregroundStyle(
            text.isEmpty ? Color(.General.Label.tertiary)
                : Color(.General.Label.primary)
        )
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .padding(LayoutTokens.spacing12)
        .background(Color(.General.Background.Grouped.secondary))
        .clipShape(RoundedRectangle(cornerRadius: LayoutTokens.radiusSm))
        .overlay {
            RoundedRectangle(cornerRadius: LayoutTokens.radiusSm)
                .strokeBorder(Color(.General.Border.`default`), lineWidth: 1)
        }
}
#endif

struct RecordBottomSheetTranscriptField: View {
    @Binding private var transcript: String
    private let focus: FocusState<Bool>.Binding
    @Binding private var bounds: CGRect

    private let content: AnyView?
    private let help: String

    init(
        transcript: Binding<String>,
        content: AnyView?,
        help: String,
        focus: FocusState<Bool>.Binding,
        bounds: Binding<CGRect>
    ) {
        self._transcript = transcript
        self.content = content
        self.help = help
        self.focus = focus
        self._bounds = bounds
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing8) {
            if let content {
                content
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                defaultEditor
            }

            Text(help)
                .typography(Typography.subheadline)
                .foregroundStyle(Color(.General.Label.secondary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var defaultEditor: some View {
#if os(watchOS)
        recordSheetReadOnlyText(transcript)
#else
        TextEditor(text: $transcript)
            .labcordTextEditorStyle(
                text: transcript,
                focus: focus,
                placeholder: Text("내용을 입력해 주세요")
            )
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .global)
            } action: { frame in
                bounds = frame
            }
            .accessibilityLabel(Text("음성 전사"))
#endif
    }
}

public extension RecordBottomSheet {
    init<MediaContent: View, MemoContent: View>(
        type: RecordType = .timer,
        contentState: RecordContentState = .empty,
        setDuration: String = "30초",
        timerIdentity: TimerIdentity = .identity01,
        timerState: TimerRecordState = .start,
        timerElapsedTime: String = "4초 실행",
        timerCumulativeTime: String = "4초",
        timerPauseCount: String = "(1)",
        voiceDuration: String = "00:08",
        voiceIsPlaying: Binding<Bool> = .constant(false),
        voiceProgress: Binding<Double> = .constant(0),
        voiceOnEditingChanged: ((Bool) -> Void)? = nil,
        voiceOnToggle: (() -> Void)? = nil,
        voiceOnSeek: ((Double) -> Void)? = nil,
        transcript: Binding<String> = .constant(
            "샘플 B, 반응 시작 5분 후 연한 노란색으로 변했고 침전은 없음"
        ),
        memo: Binding<String> = .constant(""),
        onDismiss: (() -> Void)? = nil,
        onSave: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {},
        @ViewBuilder mediaContent: () -> MediaContent,
        @ViewBuilder memoContent: () -> MemoContent
    ) {
        self.init(
            type: type,
            contentState: contentState,
            setDuration: setDuration,
            timerIdentity: timerIdentity,
            timerState: timerState,
            timerElapsedTime: timerElapsedTime,
            timerCumulativeTime: timerCumulativeTime,
            timerPauseCount: timerPauseCount,
            voiceDuration: voiceDuration,
            voiceIsPlaying: voiceIsPlaying,
            voiceProgress: voiceProgress,
            voiceOnEditingChanged: voiceOnEditingChanged,
            voiceOnToggle: voiceOnToggle,
            voiceOnSeek: voiceOnSeek,
            transcript: transcript,
            memo: memo,
            mediaContent: AnyView(mediaContent()),
            memoContent: AnyView(memoContent()),
            onDismiss: onDismiss,
            onSave: onSave,
            onDelete: onDelete
        )
    }

    init<TranscriptContent: View>(
        type: RecordType = .timer,
        contentState: RecordContentState = .empty,
        setDuration: String = "30초",
        timerIdentity: TimerIdentity = .identity01,
        timerState: TimerRecordState = .start,
        timerElapsedTime: String = "4초 실행",
        timerCumulativeTime: String = "4초",
        timerPauseCount: String = "(1)",
        voiceDuration: String = "00:08",
        voiceIsPlaying: Binding<Bool> = .constant(false),
        voiceProgress: Binding<Double> = .constant(0),
        voiceOnEditingChanged: ((Bool) -> Void)? = nil,
        voiceOnToggle: (() -> Void)? = nil,
        voiceOnSeek: ((Double) -> Void)? = nil,
        transcript: Binding<String> = .constant(
            "샘플 B, 반응 시작 5분 후 연한 노란색으로 변했고 침전은 없음"
        ),
        memo: Binding<String> = .constant(""),
        mediaContent: AnyView? = nil,
        memoContent: AnyView? = nil,
        transcriptHelp: String = "잘못 인식된 용어와 수치를 확인해 주세요.",
        onDismiss: (() -> Void)? = nil,
        onSave: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {},
        @ViewBuilder transcriptContent: () -> TranscriptContent
    ) {
        self.init(
            type: type,
            contentState: contentState,
            setDuration: setDuration,
            timerIdentity: timerIdentity,
            timerState: timerState,
            timerElapsedTime: timerElapsedTime,
            timerCumulativeTime: timerCumulativeTime,
            timerPauseCount: timerPauseCount,
            voiceDuration: voiceDuration,
            voiceIsPlaying: voiceIsPlaying,
            voiceProgress: voiceProgress,
            voiceOnEditingChanged: voiceOnEditingChanged,
            voiceOnToggle: voiceOnToggle,
            voiceOnSeek: voiceOnSeek,
            transcript: transcript,
            memo: memo,
            mediaContent: mediaContent,
            transcriptContent: AnyView(transcriptContent()),
            memoContent: memoContent,
            transcriptHelp: transcriptHelp,
            onDismiss: onDismiss,
            onSave: onSave,
            onDelete: onDelete
        )
    }

    init(
        timerSetDuration: String,
        timerIdentity: TimerIdentity,
        timerState: TimerRecordState,
        timerElapsedTime: String,
        timerCumulativeTime: String,
        timerPauseCount: String,
        contentState: RecordContentState,
        memo: Binding<String>,
        onDismiss: (() -> Void)? = nil,
        onSave: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.init(
            type: .timer, contentState: contentState, setDuration: timerSetDuration,
            timerIdentity: timerIdentity, timerState: timerState,
            timerElapsedTime: timerElapsedTime, timerCumulativeTime: timerCumulativeTime,
            timerPauseCount: timerPauseCount, memo: memo,
            onDismiss: onDismiss, onSave: onSave, onDelete: onDelete
        )
    }

    init(
        voiceDuration: String,
        isPlaying: Binding<Bool>,
        progress: Binding<Double>,
        transcript: Binding<String>,
        memo: Binding<String>,
        contentState: RecordContentState,
        onEditingChanged: ((Bool) -> Void)? = nil,
        onToggle: (() -> Void)? = nil,
        onSeek: ((Double) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        onSave: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.init(
            type: .voice, contentState: contentState,
            voiceDuration: voiceDuration, voiceIsPlaying: isPlaying, voiceProgress: progress,
            voiceOnEditingChanged: onEditingChanged, voiceOnToggle: onToggle, voiceOnSeek: onSeek,
            transcript: transcript, memo: memo,
            onDismiss: onDismiss, onSave: onSave, onDelete: onDelete
        )
    }

    init<PhotoContent: View>(
        photoContent: PhotoContent,
        contentState: RecordContentState,
        memo: Binding<String>,
        onDismiss: (() -> Void)? = nil,
        onSave: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.init(
            type: .photo, contentState: contentState, memo: memo,
            mediaContent: AnyView(photoContent),
            onDismiss: onDismiss, onSave: onSave, onDelete: onDelete
        )
    }

    init<VideoContent: View>(
        videoContent: VideoContent,
        contentState: RecordContentState,
        memo: Binding<String>,
        onDismiss: (() -> Void)? = nil,
        onSave: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.init(
            type: .video, contentState: contentState, memo: memo,
            mediaContent: AnyView(videoContent),
            onDismiss: onDismiss, onSave: onSave, onDelete: onDelete
        )
    }
}
