import SwiftUI

public struct ExperimentControlButton<Icon: View>: View {
    public enum State: String, CaseIterable, Sendable {
        case `default`
        case disabled
    }

    private let state: State
    private let action: () -> Void
    private let icon: Icon

    public init(
        state: State = .default,
        action: @escaping () -> Void,
        icon: Icon
    ) {
        self.state = state
        self.action = action
        self.icon = icon
    }

    public init(
        state: State = .default,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self.state = state
        self.action = action
        self.icon = icon()
    }

    public var body: some View {
        Button(action: action) {
            icon
                .frame(minWidth: 20, minHeight: 20)
        }
        .buttonStyle(
            RunIconButtonStyle(
                background: Color(.Experiment.Fill.primary),
                foreground: Color(.Experiment.Label.secondary),
                iconSize: 20
            )
        )
        .disabled(state == .disabled)
        .accessibilityLabel(Text("실험 제어"))
        .accessibilityValue(Text(state.accessibilityValue))
    }
}

private extension ExperimentControlButton.State {
    var accessibilityValue: String {
        switch self {
        case .default:
            "사용 가능"
        case .disabled:
            "사용할 수 없음"
        }
    }
}

#Preview("Experiment Control Button") {
    _ = FontRegistration.register()
    return HStack(spacing: 16) {
        ExperimentControlButton(
            action: noExperimentControlAction,
            icon: LabcordIconArtwork(icon: .arrowsCounterClockwise, size: 20)
        )
        ExperimentControlButton(
            state: .disabled,
            action: noExperimentControlAction,
            icon: LabcordIconArtwork(icon: .arrowsCounterClockwise, size: 20)
        )
    }
    .padding()
    .background(Color(.Experiment.Background.primary))
}

private func noExperimentControlAction() { }
