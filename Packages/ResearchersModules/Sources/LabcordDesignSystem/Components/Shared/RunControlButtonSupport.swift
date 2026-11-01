import SwiftUI

@MainActor
struct RunIconButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color
    let iconSize: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        RunIconButtonContent(
            configuration: configuration,
            background: background,
            foreground: foreground,
            iconSize: iconSize
        )
    }
}

private struct RunIconButtonContent: View {
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var buttonSize = 50.0

    let configuration: ButtonStyleConfiguration
    let background: Color
    let foreground: Color
    let iconSize: CGFloat

    private var isPressed: Bool {
        configuration.isPressed && isEnabled
    }

    var body: some View {
        configuration.label
            .frame(minWidth: iconSize, minHeight: iconSize)
            .foregroundStyle(
                isEnabled ? foreground : Color(.Experiment.Label.disabled)
            )
            .frame(width: buttonSize, height: buttonSize)
            .background(
                isEnabled ? background : Color(.Experiment.Fill.disabled),
                in: Circle()
            )
            .contentShape(Circle())
            .labcordPressFeedback(isPressed)
            .labcordMotion(.state, value: background)
    }
}
