import Foundation
import SwiftUI

public struct TimerItem<ID: Hashable>: View {
    public enum Format: String, CaseIterable, Sendable {
        case minuteSecond
        case hourMinuteSecond
    }

    public enum State: String, CaseIterable, Sendable {
        case running
        case paused
        case completed
    }

    private let timerID: ID
    private let remainingTime: String
    private let setDuration: String
    private let format: Format
    private let state: State
    private let onToggle: () -> Void
    private let onRemove: () -> Void
    private let layout = LayoutTokens()

    public init(
        _ timerID: ID,
        remainingTime: Duration,
        setDuration: Duration,
        format: Format = .minuteSecond,
        state: State,
        onToggle: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.init(
            timerID: timerID,
            remainingTime: remainingTime.formatted(
                .labcordClock(includesHours: format == .hourMinuteSecond)
            ),
            setDuration: setDuration.formatted(.labcordDuration),
            format: format,
            state: state,
            onToggle: onToggle,
            onRemove: onRemove
        )
    }

    public init(
        timerID: ID,
        remainingTime: String,
        setDuration: String,
        format: Format = .minuteSecond,
        state: State = .running,
        onToggle: @escaping () -> Void = {},
        onRemove: @escaping () -> Void = {}
    ) {
        self.timerID = timerID
        self.remainingTime = remainingTime
        self.setDuration = setDuration
        self.format = format
        self.state = state
        self.onToggle = onToggle
        self.onRemove = onRemove
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: layout.spacing8) {
                timerText
                actionButton
            }

            VStack(alignment: .leading, spacing: layout.spacing8) {
                timerText
                HStack {
                    Spacer(minLength: 0)
                    actionButton
                }
            }
        }
        .padding(layout.spacing8)
        .frame(
            maxWidth: .infinity,
            minHeight: format == .minuteSecond ? 71 : 69,
            alignment: .leading
        )
        .background {
            Rectangle()
                .fill(.labcord(.timerBackground))
                .opacity(state == .completed ? 1 : 0)
                .labcordMotion(.state, value: state.rawValue)
                .allowsHitTesting(false)
        }
        .overlay {
            Rectangle()
                .strokeBorder(.labcord(.borderDefault), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("타이머 \(String(describing: timerID))"))
        .accessibilityValue(
            Text("\(setDuration), \(remainingTime), \(state.accessibilityValue)")
        )
    }

    private var timerText: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(setDuration)
                .typography(setDurationTypography)
                .monospacedDigit()
                .foregroundStyle(.labcord(.labelTertiary))
                .contentTransition(.numericText())
                .labcordMotion(.state, value: setDuration)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(remainingTime)
                .typography(Typography.title1)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .labcordMotion(.state, value: remainingTime)
                .foregroundStyle(.labcord(remainingForeground))
                .labcordMotion(.state, value: state.rawValue)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButton: some View {
        TimerItemActionButton(
            icon: actionIcon,
            background: .timerBackground,
            foreground: .timerForeground,
            action: action
        )
    }

    private var setDurationTypography: TypographyStyle {
        switch format {
        case .minuteSecond:
            Typography.subheadline
        case .hourMinuteSecond:
            Typography.footnote
        }
    }

    private var remainingForeground: ColorToken {
        switch state {
        case .running:
            .labelPrimary
        case .paused:
            .labelTertiary
        case .completed:
            .timerForeground
        }
    }

    private var actionIcon: LabcordIcon {
        switch state {
        case .running:
            .pause
        case .paused:
            .play
        case .completed:
            .x
        }
    }

    private var action: () -> Void {
        state == .completed ? onRemove : onToggle
    }
}

private extension TimerItem.State {
    var accessibilityValue: String {
        switch self {
        case .running:
            "진행 중"
        case .paused:
            "일시 정지"
        case .completed:
            "완료"
        }
    }
}

private struct TimerItemActionButton: View {
    let icon: LabcordIcon
    let background: ColorToken
    let foreground: ColorToken
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                LabcordIconArtwork(icon: icon, size: 24, relativeTo: .body)
                    .id(icon.rawValue)
                    .transition(.opacity)
            }
            .labcordMotion(.state, value: icon.rawValue)
        }
        .buttonStyle(
            RunIconButtonStyle(
                background: background,
                foreground: foreground,
                iconSize: 24
            )
        )
        .accessibilityLabel(Text(icon.accessibilityLabel))
    }
}

private extension LabcordIcon {
    var accessibilityLabel: String {
        switch self {
        case .pause:
            "일시 정지"
        case .play:
            "타이머 재개"
        case .x:
            "타이머 제거"
        default:
            "타이머 제어"
        }
    }
}

#if DEBUG
private func noTimerAction() { }
#Preview("실행 중") {
    _ = FontRegistration.register()
    return TimerItem(
        timerID: "timer-1",
        remainingTime: "00:30",
        setDuration: "30초",
        onToggle: noTimerAction
    )
    .frame(width: 297)
    .padding()
    .background(.labcord(.backgroundPrimary))
    .labcordTheme(LabcordTheme(context: .experiment))
}

#Preview("일시 정지 · 큰 글자") {
    _ = FontRegistration.register()
    return TimerItem(
        timerID: "timer-2",
        remainingTime: "01:00:05",
        setDuration: "1시간 5분",
        format: .hourMinuteSecond,
        state: .paused,
        onToggle: noTimerAction
    )
    .frame(width: 297)
    .environment(\.dynamicTypeSize, .accessibility3)
    .padding()
    .background(.labcord(.backgroundPrimary))
    .labcordTheme(LabcordTheme(context: .experiment))
}

#Preview("완료") {
    _ = FontRegistration.register()
    return TimerItem(
        timerID: "timer-3",
        remainingTime: "00:00",
        setDuration: "30초",
        state: .completed,
        onRemove: noTimerAction
    )
    .frame(width: 297)
    .padding()
    .background(.labcord(.backgroundPrimary))
    .labcordTheme(LabcordTheme(context: .experiment))
}
#endif
