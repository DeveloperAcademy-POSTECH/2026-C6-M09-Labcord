import SwiftUI

public struct TimerControlButton: View {
    public enum State: String, CaseIterable, Sendable {
        case `default`
        case running
        case disabled
    }

    private let state: State
    private let action: () -> Void

    public init(
        state: State = .default,
        action: @escaping () -> Void
    ) {
        self.state = state
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            LabcordIconArtwork(icon: .timer, size: 20, relativeTo: .body)
        }
        .buttonStyle(
            RunIconButtonStyle(
                background: state == .running ? .timerBackground : .fillPrimary,
                foreground: .timerForeground,
                iconSize: 20
            )
        )
        .disabled(state == .disabled)
        .accessibilityLabel(Text("타이머"))
        .accessibilityValue(Text(state.accessibilityValue))
    }
}

private extension TimerControlButton.State {
    var accessibilityValue: String {
        switch self {
        case .default:
            "시작"
        case .running:
            "진행 중"
        case .disabled:
            "사용할 수 없음"
        }
    }
}

#if DEBUG
#Preview("Timer Control Button") {
    _ = FontRegistration.register()
    return HStack(spacing: 16) {
        TimerControlButton(action: noTimerControlAction)
        TimerControlButton(state: .running, action: noTimerControlAction)
        TimerControlButton(state: .disabled, action: noTimerControlAction)
    }
    .padding()
    .background(.labcord(.backgroundPrimary))
    .labcordTheme(LabcordTheme(context: .experiment))
}

private func noTimerControlAction() { }
#endif
