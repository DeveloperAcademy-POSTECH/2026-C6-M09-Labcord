import SwiftUI
#if os(iOS)
import UIKit
#endif

public enum RecordType: String, CaseIterable, Sendable {
    case timer
    case voice
    case photo
    case video
}

public enum RecordContentState: String, CaseIterable, Sendable {
    case empty
    case filled
}

public enum RecordBottomSheetScrollTarget: Hashable, Sendable {
    case transcript
    case actions
}

public struct RecordBottomSheetHeader: View {
    private let onDismiss: () -> Void
    @ScaledMetric(relativeTo: .body) private var controlScale: CGFloat = 1

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: LayoutTokens.spacing16) {
            Capsule()
                .fill(Color(.General.Fill.quaternary))
                .frame(width: 36, height: 5)
                .accessibilityHidden(true)

            HStack(alignment: .center) {
                Button(action: onDismiss) {
                    IconArtwork(icon: .x, size: 24, relativeTo: .body)
                        .foregroundStyle(Color(.General.Label.secondary))
                }
                .buttonStyle(.labcordIcon(.plain, size: .large))
                .accessibilityLabel(Text("닫기"))

                Text("기록")
                    .typography(Typography.bodySemiBold)
                    .foregroundStyle(Color(.General.Label.primary))
                    .frame(maxWidth: .infinity)

                Color.clear.frame(width: 50 * controlScale, height: 50 * controlScale)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, LayoutTokens.spacing16)
        .padding(.top, LayoutTokens.spacing16)
        .padding(.bottom, LayoutTokens.spacing16)
        .frame(maxWidth: .infinity)
        .background(Color(.General.Background.Grouped.secondary))
    }
}

public struct RecordBottomSheet: View {
    private let type: RecordType
    private let contentState: RecordContentState
    private let setDuration: String
    private let timerIdentity: TimerIdentity
    private let timerState: TimerRecordState
    private let timerElapsedTime: String
    private let timerCumulativeTime: String
    private let timerPauseCount: String
    private let voiceDuration: String
    private let voiceIsPlaying: Binding<Bool>
    private let voiceProgress: Binding<Double>
    private let voiceOnEditingChanged: ((Bool) -> Void)?
    private let voiceOnToggle: (() -> Void)?
    private let voiceOnSeek: ((Double) -> Void)?
    private let voiceContent: AnyView?
    private let mediaContent: AnyView?
    private let transcriptContent: AnyView?
    private let noteContent: AnyView?
    private let transcriptHelp: String
    private let onDismiss: (() -> Void)?
    private let onScrollTargetChange: ((RecordBottomSheetScrollTarget?) -> Void)?
    private let onSave: () -> Void
    private let onDelete: () -> Void
    private let showsActions: Bool
    private let showsHeader: Bool

    @Binding private var note: String
    @Binding private var transcript: String
    @FocusState private var isNoteFocused: Bool
    @FocusState private var isTranscriptFocused: Bool
    @State private var noteBounds = CGRect.zero
    @State private var transcriptBounds = CGRect.zero
    @State private var isKeyboardVisible = false

    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss

    public init(
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
        voiceContent: AnyView? = nil,
        transcript: Binding<String> = .constant(
            "샘플 B, 반응 시작 5분 후 연한 노란색으로 변했고 침전은 없음"
        ),
        note: Binding<String> = .constant(""),
        mediaContent: AnyView? = nil,
        transcriptContent: AnyView? = nil,
        noteContent: AnyView? = nil,
        transcriptHelp: String = "잘못 인식된 용어와 수치를 확인해 주세요.",
        onDismiss: (() -> Void)? = nil,
        onScrollTargetChange: ((RecordBottomSheetScrollTarget?) -> Void)? = nil,
        onSave: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {},
        showsActions: Bool = true,
        showsHeader: Bool = true
    ) {
        self.type = type
        self.contentState = contentState
        self.setDuration = setDuration
        self.timerIdentity = timerIdentity
        self.timerState = timerState
        self.timerElapsedTime = timerElapsedTime
        self.timerCumulativeTime = timerCumulativeTime
        self.timerPauseCount = timerPauseCount
        self.voiceDuration = voiceDuration
        self.voiceIsPlaying = voiceIsPlaying
        self.voiceProgress = voiceProgress
        self.voiceOnEditingChanged = voiceOnEditingChanged
        self.voiceOnToggle = voiceOnToggle
        self.voiceOnSeek = voiceOnSeek
        self.voiceContent = voiceContent
        self._transcript = transcript
        self._note = note
        self.mediaContent = mediaContent
        self.transcriptContent = transcriptContent
        self.noteContent = noteContent
        self.transcriptHelp = transcriptHelp
        self.onDismiss = onDismiss
        self.onScrollTargetChange = onScrollTargetChange
        self.onSave = onSave
        self.onDelete = onDelete
        self.showsActions = showsActions
        self.showsHeader = showsHeader
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                RecordBottomSheetHeader(onDismiss: close)
            }

            VStack(alignment: .center, spacing: LayoutTokens.spacing24) {
                if type == .voice {
                    VStack(alignment: .center, spacing: LayoutTokens.spacing8) {
                        RecordBottomSheetTranscriptField(
                            transcript: $transcript,
                            content: transcriptContent,
                            help: transcriptHelp,
                            focus: $isTranscriptFocused,
                            bounds: $transcriptBounds
                        )
                        .id(RecordBottomSheetScrollTarget.transcript)

                        recordContent
                    }
                    .padding(LayoutTokens.spacing8)
                    .frame(maxWidth: .infinity)
                    .background(
                        Color(.General.Background.Grouped.primary),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .padding(.horizontal, LayoutTokens.spacing16)
                }

                VStack(alignment: .center, spacing: LayoutTokens.spacing16) {
                    if type != .voice {
                        recordContent
                    }

                    if type != .voice || !isTranscriptFocused {
                        noteField
                    }

                    if showsActions {
                        actions
                    }
                }
                .padding(.horizontal, LayoutTokens.spacing16)
                .padding(.bottom, bottomPadding)
                .frame(maxWidth: .infinity)
                .id(RecordBottomSheetScrollTarget.actions)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            Color(.General.Background.Grouped.secondary),
            ignoresSafeAreaEdges: []
        )
        .clipShape(RoundedRectangle(cornerRadius: isPresented ? 0 : 28, style: .continuous))
        .shadow(
            color: isPresented
                ? .clear : Color(.General.Effect.Shadow.Medium.color),
            radius: EffectTokens(context: .general).shadowMediumRadius,
            x: 0,
            y: EffectTokens(context: .general).shadowMediumOffsetY
        )
        .accessibilityElement(children: .contain)
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .global).onEnded { value in
                if isNoteFocused, !noteBounds.contains(value.location) {
                    isNoteFocused = false
                }
                if isTranscriptFocused, !transcriptBounds.contains(value.location) {
                    isTranscriptFocused = false
                }
            }
        )
        .onChange(of: isNoteFocused) { _, isFocused in
            if isFocused {
                onScrollTargetChange?(.actions)
            } else if !isTranscriptFocused {
                onScrollTargetChange?(nil)
            }
        }
        .onChange(of: isTranscriptFocused) { _, isFocused in
            if isFocused {
                onScrollTargetChange?(.transcript)
            } else if !isNoteFocused {
                onScrollTargetChange?(nil)
            }
        }
        #if os(iOS)
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        ) { _ in
            isKeyboardVisible = true
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in
            isKeyboardVisible = false
        }
        #endif
    }

    private func close() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }
}

private extension RecordBottomSheet {
    @ViewBuilder
    var recordContent: some View {
        switch type {
        case .timer:
            TimerRecord(
                setDuration: setDuration,
                elapsedTime: timerElapsedTime,
                cumulativeTime: timerCumulativeTime,
                pauseCount: timerPauseCount,
                state: timerState,
                identity: timerIdentity,
                durationFollowsTitle: true
            )
        case .voice:
            Group {
                if let voiceContent {
                    voiceContent
                } else {
                    VoicePlayer(
                        isPlaying: voiceIsPlaying,
                        progress: voiceProgress,
                        duration: voiceDuration,
                        onEditingChanged: voiceOnEditingChanged,
                        onToggle: voiceOnToggle,
                        onSeek: voiceOnSeek
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutTokens.spacing8)
        case .photo, .video:
            Group {
                if let mediaContent {
                    mediaContent
                } else {
                    Color.clear
                }
            }
                .aspectRatio(type == .video ? 358.0 / 201.0 : 16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, type == .video ? 6 : 0)
        }
    }

    var noteField: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing8) {
            Text("메모")
                .typography(Typography.calloutSemiBold)
                .foregroundStyle(Color(.General.Label.secondary))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let noteContent {
                noteContent
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                defaultNoteEditor
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var actions: some View {
        HStack(spacing: LayoutTokens.spacing12) {
            Button(role: .destructive, action: onDelete) {
                Text("삭제")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.labcord(.quaternary, size: .large))
            .frame(maxWidth: .infinity)
            .accessibilityHint(Text("이 기록을 삭제합니다"))

            Button(action: onSave) {
                Text("저장")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.labcord(.primary, size: .large))
            .frame(maxWidth: .infinity)
            .disabled(!canSave)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    var canSave: Bool {
        contentState == .filled
    }

    var bottomPadding: CGFloat {
        let base = isPresented ? 0 : LayoutTokens.spacing32
        return base + (isKeyboardVisible ? LayoutTokens.spacing16 : 0)
    }

    @ViewBuilder
    var defaultNoteEditor: some View {
#if os(watchOS)
        recordSheetReadOnlyText(note)
#else
        VStack(alignment: .trailing, spacing: LayoutTokens.spacing8) {
            RecordBottomSheetTextEditor(
                text: $note,
                focus: $isNoteFocused,
                bounds: $noteBounds,
                accessibilityLabel: "메모",
                characterLimit: 300
            )

            Text("\(note.count)/300")
                .typography(Typography.subheadline)
                .foregroundStyle(Color(.General.Label.tertiary))
        }
#endif
    }

}
