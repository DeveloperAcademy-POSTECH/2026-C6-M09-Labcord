import Foundation
import SwiftUI

public enum LabcordTimerRecordState: String, CaseIterable, Sendable {
    case start
    case paused
    case resume
    case end
    case deleted

    fileprivate var title: String {
        switch self {
        case .start:
            "타이머 실행"
        case .paused:
            "타이머 일시정지"
        case .resume:
            "타이머 재개"
        case .end:
            "타이머 종료"
        case .deleted:
            "타이머 삭제"
        }
    }
}

public enum LabcordTimerIdentity: String, CaseIterable, Sendable {
    case identity01
    case identity02
    case identity03
    case identity04
    case identity05

    fileprivate var colorToken: ColorToken {
        switch self {
        case .identity01:
            .timerIdentity01
        case .identity02:
            .timerIdentity02
        case .identity03:
            .timerIdentity03
        case .identity04:
            .timerIdentity04
        case .identity05:
            .timerIdentity05
        }
    }
}

public struct TimerRecord: View {
    private let setDuration: String
    private let elapsedTime: String
    private let cumulativeTime: String
    private let pauseCount: String
    private let state: LabcordTimerRecordState
    private let identity: LabcordTimerIdentity

    @Environment(\.labcordTheme) private var theme

    public init(
        setDuration: Duration,
        elapsedTime: Duration,
        cumulativeTime: Duration,
        pauseCount: Int,
        state: LabcordTimerRecordState,
        identity: LabcordTimerIdentity
    ) {
        self.init(
            setDuration: setDuration.formatted(.labcordDuration),
            elapsedTime: elapsedTime.formatted(.labcordDuration) + " 실행",
            cumulativeTime: cumulativeTime.formatted(.labcordDuration),
            pauseCount: "(\(pauseCount))",
            state: state,
            identity: identity
        )
    }

    public init(
        setDuration: String = "30초",
        elapsedTime: String = "4초 실행",
        cumulativeTime: String = "4초",
        pauseCount: String = "(1)",
        state: LabcordTimerRecordState = .end,
        identity: LabcordTimerIdentity = .identity01
    ) {
        self.setDuration = setDuration
        self.elapsedTime = elapsedTime
        self.cumulativeTime = cumulativeTime
        self.pauseCount = pauseCount
        self.state = state
        self.identity = identity
    }

    public var body: some View {
        Group {
            if state == .paused {
                pausedContent
                    .transition(.opacity)
            } else {
                singleLineContent
                    .transition(.opacity)
            }
        }
        .labcordMotion(.layout, value: state.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var singleLineContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: theme.layout.spacing8) {
                durationLabel
                stateLabel
            }
            .fixedSize(horizontal: true, vertical: true)

            VStack(alignment: .leading, spacing: theme.layout.spacing8) {
                durationLabel
                stateLabel
            }
        }
        .frame(minHeight: 22, alignment: .leading)
    }

    private var pausedContent: some View {
        VStack(alignment: .leading, spacing: theme.layout.spacing8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: theme.layout.spacing8) {
                    durationLabel
                    pausedStatus
                }
                .fixedSize(horizontal: true, vertical: true)

                VStack(alignment: .leading, spacing: theme.layout.spacing8) {
                    durationLabel
                    pausedStatus
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: theme.layout.spacing16) {
                    elapsedDetail
                    cumulativeDetail
                }
                .fixedSize(horizontal: true, vertical: true)

                VStack(alignment: .leading, spacing: theme.layout.spacing8) {
                    elapsedDetail
                    cumulativeDetail
                }
            }
        }
    }

    private var pausedStatus: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.layout.spacing8) {
            stateLabel

            Text(pauseCount)
                .typography(Typography.bodyEmphasized)
                .foregroundStyle(.labcord(.labelPrimary))
                .contentTransition(.numericText())
                .labcordMotion(.state, value: pauseCount)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var stateLabel: some View {
        Text(state.title)
            .typography(Typography.bodyEmphasized)
            .foregroundStyle(.labcord(.labelPrimary))
            .contentTransition(.opacity)
            .labcordMotion(.state, value: state.rawValue)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var elapsedDetail: some View {
        timeDetail("시작 후", value: elapsedTime)
    }

    private var cumulativeDetail: some View {
        timeDetail("누적", value: cumulativeTime)
    }

    private func timeDetail(_ title: LocalizedStringKey, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: theme.layout.spacing8) {
                detailTitle(title)
                detailValue(value)
            }
            .fixedSize(horizontal: true, vertical: true)

            VStack(alignment: .leading, spacing: theme.layout.spacing8) {
                detailTitle(title)
                detailValue(value)
            }
        }
    }

    private func detailTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .typography(Typography.body)
            .foregroundStyle(.labcord(.labelTertiary))
    }

    private func detailValue(_ value: String) -> some View {
        Text(value)
            .typography(Typography.bodyEmphasized)
            .foregroundStyle(.labcord(.labelSecondary))
            .contentTransition(.numericText())
            .labcordMotion(.state, value: value)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var durationLabel: some View {
        Text(setDuration)
            .typography(Typography.bodyEmphasized)
            .foregroundStyle(.labcord(.labelPrimary))
            .contentTransition(.numericText())
            .labcordMotion(.state, value: setDuration)
            .padding(.leading, theme.layout.spacing4 + 3)
            .frame(minHeight: 22, alignment: .leading)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.labcord(identity.colorToken))
                    .frame(width: 3)
                    .accessibilityHidden(true)
            }
            .fixedSize(horizontal: false, vertical: true)
    }

    private var accessibilityText: String {
        if state == .paused {
            return "\(setDuration) \(state.title), \(elapsedTime), "
                + "누적 \(cumulativeTime), 일시정지 \(pauseCount)"
        }
        return "\(setDuration) \(state.title)"
    }
}

#if DEBUG
#Preview("타이머 기록 · 상태") {
    _ = FontRegistration.register()
    return VStack(alignment: .leading, spacing: 16) {
        ForEach(LabcordTimerRecordState.allCases, id: \.rawValue) { state in
            TimerRecord(state: state, identity: .identity01)
        }
    }
    .padding()
    .foregroundStyle(.labcord(.labelPrimary))
    .background(.labcord(.backgroundPrimary))
    .labcordTheme(LabcordTheme(context: .general))
}

#Preview("타이머 기록 · 큰 글자") {
    _ = FontRegistration.register()
    return TimerRecord(
        setDuration: "30초",
        elapsedTime: "4초 실행",
        cumulativeTime: "4초",
        state: .paused,
        identity: .identity02
    )
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .environment(\.dynamicTypeSize, .accessibility3)
    .labcordTheme(LabcordTheme(context: .experiment))
}
#endif
