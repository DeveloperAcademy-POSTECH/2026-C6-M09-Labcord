import LabcordDesignSystem
import Observation
import SwiftUI

struct CatalogRunTimerScenario: View {
    @State private var format = TimerItem<String>.Format.minuteSecond
    @State private var countdown = CatalogCountdown(duration: .seconds(30), phase: .running)
    @State private var isVisible = true
    @State private var actionCount = 0
    @Environment(\.scenePhase) private var scenePhase

    private var includesHours: Bool { format == .hourMinuteSecond }
    private var duration: Duration { .seconds(includesHours ? 3_605 : 30) }

    private var state: Binding<TimerItem<String>.State> {
        Binding(
            get: {
                switch countdown.phase {
                case .running: .running
                case .ready, .paused: .paused
                case .completed: .completed
                }
            },
            set: { next in
                let phase: CatalogCountdown.Phase = switch next {
                case .running: .running
                case .paused: .paused
                case .completed: .completed
                }
                countdown.reset(duration: duration, phase: phase)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isVisible {
                TimerItem(
                    "timer-1", remainingTime: .seconds(countdown.remainingSeconds),
                    setDuration: duration,
                    format: format, state: state.wrappedValue,
                    onToggle: {
                        actionCount += 1
                        if countdown.isRunning { countdown.pause() } else { countdown.start() }
                    },
                    onRemove: {
                        actionCount += 1
                        countdown.pause()
                        isVisible = false
                    }
                )
                .accessibilityIdentifier("catalog.motion.timer")
            } else {
                Button("타이머 다시 표시") {
                    countdown.reset(duration: duration, phase: .running)
                    isVisible = true
                }
                .buttonStyle(.labcord(.secondary, size: .small))
                .accessibilityIdentifier("catalog.scenario.timer.restore")
            }
            Picker("시간 형식", selection: $format) {
                Text("MM:SS").tag(TimerItem<String>.Format.minuteSecond)
                Text("HH:MM:SS").tag(TimerItem<String>.Format.hourMinuteSecond)
            }
            .accessibilityIdentifier("catalog.scenario.timer.format")
            Picker("상태", selection: state) {
                Text("Running").tag(TimerItem<String>.State.running)
                Text("Paused").tag(TimerItem<String>.State.paused)
                Text("Completed").tag(TimerItem<String>.State.completed)
            }
            .disabled(!isVisible)
            .accessibilityIdentifier("catalog.scenario.timer.state")
            Button("타이머 재설정") { countdown.reset(duration: duration, phase: .paused) }
                .buttonStyle(.labcord(.secondary, size: .small))
                .disabled(!isVisible)
                .accessibilityIdentifier("catalog.motion.timerTick")
            Text("제어 \(actionCount)회")
                .typography(Typography.caption1)
                .monospacedDigit()
                .accessibilityIdentifier("catalog.scenario.timer.actionCount")
        }
        .task(id: isVisible && countdown.isRunning && scenePhase == .active) {
            guard isVisible, countdown.isRunning, scenePhase == .active else { return }
            await countdown.run()
        }
        .onChange(of: format) { _, _ in
            countdown.reset(duration: duration, phase: countdown.phase)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { countdown.refresh() }
        }
    }
}

struct CatalogRunRecordButtonScenario: View {
    @State private var kind = RecordButton.Kind.audio
    @State private var state = RecordButton.State.default
    @State private var actionCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RecordButton(type: kind, state: state) { actionCount += 1 }
                .accessibilityIdentifier("catalog.scenario.recordButton.preview")
            Picker("기록 종류", selection: $kind) {
                catalogPickerOptions(RecordButton.Kind.allCases)
            }
            .accessibilityIdentifier("catalog.scenario.recordButton.kind")
            Picker("상태", selection: $state) {
                catalogPickerOptions(RecordButton.State.allCases)
            }
            .accessibilityIdentifier("catalog.scenario.recordButton.state")
            Text("실행 \(actionCount)회")
                .typography(Typography.caption1)
                .monospacedDigit()
                .accessibilityIdentifier("catalog.scenario.recordButton.actionCount")
        }
    }
}

struct CatalogRunExperimentControlScenario: View {
    @State private var isDisabled = false
    @State private var icon = LabcordIcon.arrowsCounterClockwise
    @State private var actionCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExperimentControlButton(
                state: isDisabled ? .disabled : .default,
                action: { actionCount += 1 }, icon: Image(labcordIcon: icon)
            )
            .accessibilityIdentifier("catalog.scenario.experimentControl.preview")
            Picker("상태", selection: $isDisabled) {
                Text("Default").tag(false)
                Text("Disabled").tag(true)
            }
            .accessibilityIdentifier("catalog.scenario.experimentControl.state")
            Picker("아이콘", selection: $icon) {
                ForEach(LabcordIcon.allCases) { icon in Text(icon.rawValue).tag(icon) }
            }
            .accessibilityIdentifier("catalog.scenario.experimentControl.icon")
            Text("실행 \(actionCount)회")
                .typography(Typography.caption1)
                .monospacedDigit()
                .accessibilityIdentifier("catalog.scenario.experimentControl.actionCount")
        }
    }
}

struct CatalogRunTimerControlScenario: View {
    @State private var state = TimerControlButton.State.default
    @State private var duration = Duration.seconds(30)
    @State private var countdown = CatalogCountdown()
    @State private var isFullScreen = true
    @State private var event = "시간을 선택하고 타이머를 시작해 주세요"
    @Environment(\.scenePhase) private var scenePhase

    private var stateSelection: Binding<TimerControlButton.State> {
        Binding(get: { state }, set: { next in
            state = next
            countdown.reset(duration: duration, phase: next == .running ? .running : .ready)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimerControlButton(state: state) {
                if state == .running {
                    isFullScreen = false
                    event = "진행 중인 타이머를 선택해 카메라 화면을 축소했어요."
                } else {
                    countdown.reset(duration: duration, phase: .running)
                    state = .running
                    event = "타이머가 실행됐어요."
                }
            }
            .disabled(duration <= .zero && state != .running)
            .accessibilityIdentifier("catalog.motion.timerControl")
            TimerPicker(duration: $duration)
                .disabled(countdown.isRunning)
                .accessibilityIdentifier("catalog.scenario.timerControl.duration")
            CatalogCountdownStatus(
                remainingSeconds: countdown.remainingSeconds,
                digitCount: String(max(0, duration.components.seconds)).count
            )
                .typography(Typography.footnote)
                .foregroundStyle(Color("Experiment/Label/Secondary", bundle: catalogBundle))
                .accessibilityIdentifier("catalog.scenario.timerControl.remaining")
            if state == .running {
                Button(countdown.isRunning ? "일시정지" : "재개") {
                    if countdown.isRunning { countdown.pause() } else { countdown.start() }
                }
                .buttonStyle(.labcord(.secondary, size: .small))
                .accessibilityIdentifier("catalog.scenario.timerControl.pauseResume")
            }
            cameraPreview
            Picker("상태", selection: stateSelection) {
                catalogPickerOptions(TimerControlButton.State.allCases)
            }
            .accessibilityIdentifier("catalog.scenario.timerControl.state")
            Button("카메라 전체 화면 보기") { isFullScreen = true }
                .buttonStyle(.labcord(.secondary, size: .small))
                .accessibilityIdentifier("catalog.scenario.timerControl.expandCamera")
            Button("타이머 종료 이벤트", action: finishTimer)
                .buttonStyle(.labcord(.secondary, size: .small))
                .disabled(state != .running)
                .accessibilityIdentifier("catalog.scenario.timerControl.finish")
            Text(event)
                .typography(Typography.caption1)
                .foregroundStyle(Color("Experiment/Label/Secondary", bundle: catalogBundle))
                .accessibilityIdentifier("catalog.scenario.timerControl.event")
        }
        .task(id: countdown.isRunning && scenePhase == .active) {
            guard countdown.isRunning, scenePhase == .active else { return }
            await countdown.run()
        }
        .onChange(of: duration) { _, _ in
            guard !countdown.isRunning else { return }
            countdown.reset(duration: duration)
            state = .default
        }
        .onChange(of: countdown.isCompleted) { _, completed in
            if completed { finishTimer() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { countdown.refresh() }
        }
    }

    private func finishTimer() {
        countdown.finish()
        state = .default
        isFullScreen = false
        event = "타이머 종료로 카메라 화면을 축소했어요."
    }

    private var cameraPreview: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color("Experiment/Border/Default", bundle: catalogBundle))
            .frame(height: isFullScreen ? 160 : 80)
            .overlay {
                Label {
                    Text(isFullScreen ? "카메라 전체 화면" : "카메라 축소 화면")
                } icon: {
                    Image(labcordIcon: .capture)
                }
                .typography(Typography.caption1)
            }
            .labcordMotion(.layout, value: isFullScreen)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("catalog.scenario.timerControl.cameraState")
    }
}

@Observable
@MainActor
final class CatalogCountdown {
    enum Phase: Equatable { case ready, running, paused, completed }

    private(set) var phase = Phase.ready
    private(set) var remainingSeconds: Int64 = 0
    @ObservationIgnored private var remainingDuration = Duration.zero
    @ObservationIgnored private var deadline: ContinuousClock.Instant?
    @ObservationIgnored private let clock = ContinuousClock()

    var isRunning: Bool { phase == .running }
    var hasStarted: Bool { phase != .ready }
    var isCompleted: Bool { phase == .completed }

    init(duration: Duration = .seconds(30), phase: Phase = .ready) {
        reset(duration: duration, phase: phase)
    }

    func reset(duration: Duration, phase: Phase = .ready) {
        deadline = nil
        remainingDuration = max(.zero, duration)
        self.phase = phase == .completed ? .completed : .ready
        publish(phase == .completed ? .zero : remainingDuration)
        switch phase {
        case .running: start()
        case .paused: self.phase = .paused
        case .completed: remainingDuration = .zero
        case .ready: break
        }
    }

    func start() {
        guard !isRunning else { return }
        guard remainingDuration > .zero else { finish(); return }
        deadline = clock.now.advanced(by: remainingDuration)
        phase = .running
        refresh()
    }

    func pause() {
        guard isRunning, let deadline else { return }
        remainingDuration = max(.zero, clock.now.duration(to: deadline))
        self.deadline = nil
        phase = remainingDuration > .zero ? .paused : .completed
        publish(remainingDuration)
    }

    func finish() {
        deadline = nil
        remainingDuration = .zero
        phase = .completed
        publish(.zero)
    }

    func refresh() {
        guard isRunning, let deadline else { return }
        let remaining = max(Duration.zero, clock.now.duration(to: deadline))
        if remaining == .zero { finish() } else { publish(remaining) }
    }

    func run() async {
        while isRunning, !Task.isCancelled {
            refresh()
            guard isRunning else { return }
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch { return }
        }
    }

    private func publish(_ duration: Duration) {
        let components = max(Duration.zero, duration).components
        let rounded = components.attoseconds > 0 && components.seconds < Int64.max
            ? components.seconds + 1 : components.seconds
        if remainingSeconds != rounded { remainingSeconds = rounded }
    }
}

struct CatalogCountdownStatus: View {
    let remainingSeconds: Int64
    let digitCount: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("남은 시간 ")
            Text(String(repeating: "0", count: max(1, digitCount)))
                .hidden()
                .overlay(alignment: .trailing) {
                    Text(remainingSeconds, format: .number.grouping(.never))
                        .contentTransition(.numericText(countsDown: true))
                        .labcordMotion(.state, value: remainingSeconds)
                }
                .monospacedDigit()
            Text("초")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("남은 시간 \(remainingSeconds)초"))
    }
}
