import AVFoundation
import LabcordDesignSystem
import Observation
import SwiftUI

struct CatalogVoiceSample: View {
    var showDuration = true
    @State private var playback = CatalogAudioPlayback()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VoicePlayer(
            isPlaying: playback.isPlayingBinding,
            progress: playback.progressBinding,
            duration: "00:08",
            showDuration: showDuration,
            onEditingChanged: playback.setEditing
        )
        .task(id: playback.isPlaying) { await playback.updateProgress() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { playback.stop() }
        }
        .onDisappear { playback.stop() }
    }
}

struct CatalogRecordSheetSample: View {
    let type: RecordType
    let identity: TimerIdentity
    var timerExample = CatalogTimerRecordExample.short
    @Binding var memo: String
    @Binding var transcript: String
    var initialTranscript: String?
    let onDismiss: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    @State private var playback = CatalogAudioPlayback()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        RecordBottomSheet(
            type: type,
            contentState: canSave ? .filled : .empty,
            setDuration: timerExample.setDuration,
            timerIdentity: identity,
            timerState: timerExample.sheetState,
            timerElapsedTime: timerExample.elapsedTime,
            timerCumulativeTime: timerExample.cumulativeTime,
            timerPauseCount: "(1)",
            voiceIsPlaying: playback.isPlayingBinding,
            voiceProgress: playback.progressBinding,
            voiceOnEditingChanged: playback.setEditing,
            transcript: $transcript,
            memo: $memo,
            mediaContent: mediaContent,
            memoContent: AnyView(CatalogTextEditor(value: $memo)),
            onDismiss: onDismiss,
            onSave: onSave,
            onDelete: onDelete
        )
        .task(id: playback.isPlaying) {
            if type == .voice { await playback.updateProgress() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { playback.stop() }
        }
        .onDisappear { playback.stop() }
    }

    private var canSave: Bool {
        !memo.isEmpty || (type == .voice && initialTranscript.map { transcript != $0 } == true)
    }

    private var mediaContent: AnyView? {
        switch type {
        case .photo: AnyView(CatalogSampleMedia())
        case .video: AnyView(CatalogLoopingVideo())
        case .timer, .voice: nil
        }
    }
}

enum CatalogTimerRecordExample: String, CaseIterable {
    case short = "기본"
    case longFirst = "긴 기록 1"
    case longSecond = "긴 기록 2"

    var setDuration: String { self == .short ? "30초" : "23:59:59시간" }
    var sheetState: TimerRecordState { self == .short ? .start : .paused }

    var elapsedTime: String {
        switch self {
        case .short: "4초 실행"
        case .longFirst: "10:59:59시간"
        case .longSecond: "2시간"
        }
    }

    var cumulativeTime: String {
        switch self {
        case .short: "4초"
        case .longFirst: "10:59:59시간"
        case .longSecond: "12:59:59시간"
        }
    }
}

@Observable
@MainActor
private final class CatalogAudioPlayback {
    private static weak var activePlayback: CatalogAudioPlayback?
    private(set) var isPlaying = false
    private(set) var progress = 0.25
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var sessionIsActive = false
    @ObservationIgnored private var resumesAfterEditing = false

    var isPlayingBinding: Binding<Bool> {
        Binding(get: { self.isPlaying }, set: { $0 ? self.play() : self.pause() })
    }

    var progressBinding: Binding<Double> {
        Binding(get: { self.progress }, set: { self.seek($0) })
    }

    func updateProgress() async {
        while isPlaying, !Task.isCancelled {
            guard let player, player.isPlaying else { stop(); return }
            progress = player.duration > 0 ? player.currentTime / player.duration : 0
            do {
                try await Task.sleep(for: .milliseconds(16))
            } catch { return }
        }
    }

    func stop() {
        resumesAfterEditing = false
        pause()
        player?.stop()
        player?.currentTime = 0
        progress = 0
    }

    func setEditing(_ active: Bool) {
        if active {
            resumesAfterEditing = isPlaying
            if isPlaying { pause() }
        } else {
            let shouldResume = resumesAfterEditing
            resumesAfterEditing = false
            if shouldResume { play() }
        }
    }

    private func seek(_ value: Double) {
        guard value.isFinite else { return }
        progress = min(max(value, 0), 1)
        if let player { player.currentTime = progress * player.duration }
    }

    private func play() {
        guard !isPlaying else { return }
        do {
            if player == nil {
                guard let url = Bundle.module.url(
                    forResource: "catalog-audio-sample", withExtension: "wav"
                ) else { return }
                player = try AVAudioPlayer(contentsOf: url)
            }
            guard let player, player.duration > 0 else { return }
            if Self.activePlayback !== self { Self.activePlayback?.stop() }
            #if os(iOS) || os(watchOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try session.setActive(true)
            sessionIsActive = true
            #endif
            seek(progress >= 1 ? 0 : progress)
            guard player.play() else { pause(); return }
            Self.activePlayback = self
            isPlaying = true
        } catch { stop() }
    }

    private func pause() {
        player?.pause()
        if let player, player.duration > 0 {
            progress = player.currentTime / player.duration
        }
        isPlaying = false
        if Self.activePlayback === self { Self.activePlayback = nil }
        guard sessionIsActive else { return }
        #if os(iOS) || os(watchOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        sessionIsActive = false
    }
}

#Preview("음성 기록 예제") {
    _ = FontRegistration.register()
    return CatalogVoiceSample()
        .padding()
}

#Preview("기록 시트 예제") {
    @Previewable @State var memo = "실험 결과를 기록했어요."
    @Previewable @State var transcript = "색이 변했어요."
    _ = FontRegistration.register()
    return CatalogRecordSheetSample(
        type: .voice,
        identity: .identity02,
        memo: $memo,
        transcript: $transcript,
        onDismiss: {},
        onSave: {},
        onDelete: {}
    )
}
