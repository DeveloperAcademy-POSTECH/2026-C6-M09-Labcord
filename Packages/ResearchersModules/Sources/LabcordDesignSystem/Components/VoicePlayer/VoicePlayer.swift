import SwiftUI

public struct VoicePlayer: View {
    private let duration: String
    private let showDuration: Bool
    private let waveform: AnyView?
    private let onToggle: (() -> Void)?
    private let onSeek: ((Double) -> Void)?
    private let onEditingChanged: ((Bool) -> Void)?

    @Binding private var isPlaying: Bool
    @Binding private var progress: Double
    @State private var isSeeking = false
    @State private var isPressingSlider = false

    private let tokenLayout = LayoutTokens()
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var rowHeight = 28

    public init(
        duration: String = "00:08",
        showDuration: Bool = true,
        isPlaying: Binding<Bool> = .constant(false),
        progress: Binding<Double> = .constant(0),
        waveform: AnyView? = nil,
        onEditingChanged: ((Bool) -> Void)? = nil,
        onToggle: (() -> Void)? = nil,
        onSeek: ((Double) -> Void)? = nil
    ) {
        self.duration = duration
        self.showDuration = showDuration
        self._isPlaying = isPlaying
        self._progress = progress
        self.waveform = waveform
        self.onToggle = onToggle
        self.onSeek = onSeek
        self.onEditingChanged = onEditingChanged
    }

    public init<Waveform: View>(
        duration: String = "00:08",
        showDuration: Bool = true,
        isPlaying: Binding<Bool> = .constant(false),
        progress: Binding<Double> = .constant(0),
        onEditingChanged: ((Bool) -> Void)? = nil,
        onToggle: (() -> Void)? = nil,
        onSeek: ((Double) -> Void)? = nil,
        @ViewBuilder waveform: () -> Waveform
    ) {
        self.init(
            duration: duration,
            showDuration: showDuration,
            isPlaying: isPlaying,
            progress: progress,
            waveform: AnyView(waveform()),
            onEditingChanged: onEditingChanged,
            onToggle: onToggle,
            onSeek: onSeek
        )
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalLayout
            verticalLayout
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                isPressingSlider = false
                updateEditing(false)
            }
        }
        .onChange(of: waveform != nil) { _, hasWaveform in
            if hasWaveform {
                isPressingSlider = false
                updateEditing(false)
            }
        }
        .onDisappear {
            isPressingSlider = false
            updateEditing(false)
        }
    }

    private var horizontalLayout: some View {
        HStack(alignment: .center, spacing: tokenLayout.spacing12) {
            playButton
            Color.clear
                .frame(height: rowHeight)
                .overlay {
                    progressControl(minimumHeight: max(44, rowHeight))
                }
                .frame(minWidth: 44, maxWidth: .infinity)
            if showDuration {
                horizontalDuration
            }
        }
        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .center)
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: tokenLayout.spacing8) {
            HStack(alignment: .firstTextBaseline, spacing: tokenLayout.spacing12) {
                playButton
                if showDuration {
                    flexibleDuration
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            progressControl(minimumHeight: 44)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var horizontalDuration: some View {
        Text(duration)
            .typography(Typography.callout)
            .foregroundStyle(Color("General/Label/Secondary", bundle: .module))
            .frame(minWidth: 44)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var flexibleDuration: some View {
        Text(duration)
            .typography(Typography.callout)
            .foregroundStyle(Color("General/Label/Secondary", bundle: .module))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var playButton: some View {
        Button(action: toggle) {
            ZStack {
                LabcordIconArtwork(
                    icon: isPlaying ? .pause : .play,
                    size: 12,
                    relativeTo: .body
                )
                .id(isPlaying)
                .transition(.opacity)
            }
            .foregroundStyle(Color("General/Label/Inverse", bundle: .module))
            .labcordMotion(.state, value: isPlaying)
        }
        .buttonStyle(.labcordIcon(.primary, size: .small))
        .padding(playButtonHitInset)
        .contentShape(Rectangle())
        .padding(-playButtonHitInset)
        .accessibilityLabel(Text(isPlaying ? "일시정지" : "재생"))
        .accessibilityValue(Text(duration))
    }

    private var playButtonHitInset: CGFloat {
        max(0, (44 - rowHeight) / 2)
    }

    @ViewBuilder
    private func progressControl(minimumHeight: CGFloat? = nil) -> some View {
        Slider(value: $progress, in: 0...1) { isEditing in
            let shouldCommit = !isEditing && isSeeking && isEnabled
            let finalProgress = progress
            updateEditing(isEditing)
            if shouldCommit {
                onSeek?(finalProgress)
            }
        }
        .sliderThumbVisibility(.hidden)
        .opacity(waveform == nil ? 1 : 0.01)
        .overlay {
            if let waveform {
                waveform
                    .frame(maxWidth: .infinity, minHeight: 6, maxHeight: 6)
                    .clipShape(Capsule())
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            seekThumb
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .tint(Color("General/Brand/Primary", bundle: .module))
        .controlSize(.small)
        .frame(maxWidth: .infinity, minHeight: minimumHeight)
        .labcordSliderPressObservation($isPressingSlider)
        .accessibilityLabel(Text("음성 재생 위치"))
        .accessibilityValue(Text(progress.formatted(.percent.precision(.fractionLength(0)))))
    }

    private func updateEditing(_ isEditing: Bool) {
        let active = isEditing && isEnabled
        guard isSeeking != active else { return }
        isSeeking = active
        onEditingChanged?(active)
    }

    private var isSeekThumbVisible: Bool {
        #if os(iOS)
        isEnabled && isPressingSlider
        #else
        isEnabled && isSeeking
        #endif
    }

    private var seekThumb: some View {
        GeometryReader { geometry in
            let width = min(56, geometry.size.width)
            let position = geometry.size.width * CGFloat(min(max(progress, 0), 1))

            Capsule()
                .fill(.clear)
                .frame(width: width, height: 36)
                .glassEffect(.regular, in: .capsule)
                .scaleEffect(isSeekThumbVisible ? 1 : 0.45)
                .opacity(isSeekThumbVisible ? 1 : 0)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.12),
                    value: isSeekThumbVisible
                )
                .position(
                    x: min(max(position, width / 2), geometry.size.width - width / 2),
                    y: geometry.size.height / 2
                )
        }
    }

    private func toggle() {
        if let onToggle {
            onToggle()
        } else {
            isPlaying.toggle()
        }
    }
}

public extension VoicePlayer {
    init(
        isPlaying: Binding<Bool>,
        progress: Binding<Double>,
        duration: String,
        showDuration: Bool = true,
        waveform: AnyView? = nil,
        onEditingChanged: ((Bool) -> Void)? = nil,
        onToggle: (() -> Void)? = nil,
        onSeek: ((Double) -> Void)? = nil
    ) {
        self.init(
            duration: duration, showDuration: showDuration,
            isPlaying: isPlaying, progress: progress, waveform: waveform,
            onEditingChanged: onEditingChanged, onToggle: onToggle, onSeek: onSeek
        )
    }

    init<Waveform: View>(
        isPlaying: Binding<Bool>,
        progress: Binding<Double>,
        duration: String,
        showDuration: Bool = true,
        onEditingChanged: ((Bool) -> Void)? = nil,
        onToggle: (() -> Void)? = nil,
        onSeek: ((Double) -> Void)? = nil,
        @ViewBuilder waveform: () -> Waveform
    ) {
        self.init(
            duration: duration, showDuration: showDuration,
            isPlaying: isPlaying, progress: progress, waveform: AnyView(waveform()),
            onEditingChanged: onEditingChanged, onToggle: onToggle, onSeek: onSeek
        )
    }
}

#Preview("음성 플레이어 · 기본/재생") {
    _ = FontRegistration.register()
    return VStack(spacing: 20) {
        VoicePlayer()
        VoicePlayer(showDuration: false, isPlaying: .constant(true))
    }
    .padding()
    .frame(maxWidth: .infinity)
    .foregroundStyle(Color("General/Label/Primary", bundle: .module))
    .background(Color("General/Background/Primary", bundle: .module))
}

#Preview("음성 플레이어 · 큰 글자") {
    _ = FontRegistration.register()
    return VoicePlayer(duration: "01:28")
        .padding()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("음성 플레이어 · 좁은 폭 반응형") {
    _ = FontRegistration.register()
    return VoicePlayer(duration: "01:23:45")
        .frame(width: 200)
        .environment(\.dynamicTypeSize, .accessibility3)
        .padding()
}
