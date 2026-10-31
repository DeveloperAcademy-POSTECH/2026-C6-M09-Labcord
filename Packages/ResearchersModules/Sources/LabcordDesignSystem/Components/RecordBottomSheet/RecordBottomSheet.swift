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
    private let mediaContent: AnyView?
    private let transcriptContent: AnyView?
    private let memoContent: AnyView?
    private let transcriptHelp: String
    private let onDismiss: (() -> Void)?
    private let onSave: () -> Void
    private let onDelete: () -> Void

    @Binding private var memo: String
    @Binding private var transcript: String
    @FocusState private var isMemoFocused: Bool
    @FocusState private var isTranscriptFocused: Bool
    @State private var memoBounds = CGRect.zero
    @State private var transcriptBounds = CGRect.zero
    @State private var isKeyboardVisible = false

    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var headerControlScale: CGFloat = 1

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
        transcript: Binding<String> = .constant(
            "샘플 B, 반응 시작 5분 후 연한 노란색으로 변했고 침전은 없음"
        ),
        memo: Binding<String> = .constant(""),
        mediaContent: AnyView? = nil,
        transcriptContent: AnyView? = nil,
        memoContent: AnyView? = nil,
        transcriptHelp: String = "잘못 인식된 용어와 수치를 확인해 주세요.",
        onDismiss: (() -> Void)? = nil,
        onSave: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {}
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
        self._transcript = transcript
        self._memo = memo
        self.mediaContent = mediaContent
        self.transcriptContent = transcriptContent
        self.memoContent = memoContent
        self.transcriptHelp = transcriptHelp
        self.onDismiss = onDismiss
        self.onSave = onSave
        self.onDelete = onDelete
    }

    public var body: some View {
        VStack(alignment: .center, spacing: LayoutTokens.spacing16) {
            grabber
            header
            recordContent
            if type == .voice {
                RecordBottomSheetTranscriptField(
                    transcript: $transcript,
                    content: transcriptContent,
                    help: transcriptHelp,
                    focus: $isTranscriptFocused,
                    bounds: $transcriptBounds
                )
            }
            memoField
            actions
        }
        .padding(.horizontal, LayoutTokens.spacing16)
        .padding(.top, LayoutTokens.spacing16)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity)
        .background(
            Color("General/Background/Grouped/Secondary", bundle: .module),
            ignoresSafeAreaEdges: []
        )
        .clipShape(RoundedRectangle(cornerRadius: isPresented ? 0 : 28, style: .continuous))
        .shadow(
            color: isPresented
                ? .clear : Color("General/Effect/Shadow/Medium/Color", bundle: .module),
            radius: EffectTokens(context: .general).shadowMediumRadius,
            x: 0,
            y: EffectTokens(context: .general).shadowMediumOffsetY
        )
        .accessibilityElement(children: .contain)
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .global).onEnded { value in
                if isMemoFocused, !memoBounds.contains(value.location) {
                    isMemoFocused = false
                }
                if isTranscriptFocused, !transcriptBounds.contains(value.location) {
                    isTranscriptFocused = false
                }
            }
        )
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

    private var grabber: some View {
        Capsule()
            .fill(Color("General/Fill/Quaternary", bundle: .module))
            .frame(width: 36, height: 5)
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button(action: close) {
                LabcordIconArtwork(icon: .x, size: 16, relativeTo: .body)
                    .foregroundStyle(Color("General/Label/Primary", bundle: .module))
            }
            .buttonStyle(.labcordIcon(.tertiary, size: .medium))
            .accessibilityLabel(Text("닫기"))

            Text("기록")
                .typography(Typography.bodySemiBold)
                .foregroundStyle(Color("General/Label/Primary", bundle: .module))
                .frame(maxWidth: .infinity)

            Color.clear.frame(width: 34 * headerControlScale, height: 34 * headerControlScale)
                .accessibilityHidden(true)
        }
        .padding(.vertical, LayoutTokens.spacing4)
        .frame(maxWidth: .infinity)
    }

    private func close() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    @ViewBuilder
    private var recordContent: some View {
        switch type {
        case .timer:
            TimerRecord(
                setDuration: setDuration,
                elapsedTime: timerElapsedTime,
                cumulativeTime: timerCumulativeTime,
                pauseCount: timerPauseCount,
                state: timerState,
                identity: timerIdentity
            )
        case .voice:
            VoicePlayer(
                isPlaying: voiceIsPlaying,
                progress: voiceProgress,
                duration: voiceDuration,
                onEditingChanged: voiceOnEditingChanged,
                onToggle: voiceOnToggle,
                onSeek: voiceOnSeek
            )
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
                .aspectRatio(type == .video ? 370.0 / 201.0 : 16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()
        }
    }

    private var memoField: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing8) {
            Text("메모")
                .typography(Typography.calloutSemiBold)
                .foregroundStyle(Color("General/Label/Secondary", bundle: .module))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let memoContent {
                memoContent
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                defaultMemoEditor
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: LayoutTokens.spacing16) {
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
        .padding(.horizontal, -6)
        .frame(maxWidth: .infinity)
    }

    private var canSave: Bool {
        contentState == .filled
    }
}

private extension RecordBottomSheet {
    var bottomPadding: CGFloat {
        let base = isPresented ? 0 : LayoutTokens.spacing32
        return base + (isKeyboardVisible ? LayoutTokens.spacing16 : 0)
    }

    @ViewBuilder
    var defaultMemoEditor: some View {
#if os(watchOS)
        recordSheetReadOnlyText(memo, layout: tokenLayout)
#else
        TextEditor(text: $memo)
            .labcordTextEditorStyle(
                text: memo,
                focus: $isMemoFocused,
                placeholder: Text("내용을 입력해 주세요")
            )
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .global)
            } action: { bounds in
                memoBounds = bounds
            }
            .accessibilityLabel(Text("메모"))
#endif
    }

}

public typealias LabcordRecordBottomSheet = RecordBottomSheet
