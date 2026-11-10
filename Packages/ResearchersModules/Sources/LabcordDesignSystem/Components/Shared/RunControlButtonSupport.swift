import SwiftUI

@MainActor
struct RunIconButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color
    let iconSize: CGFloat
    var disabledBackground: Color = Color(.Experiment.Fill.disabled)
    var disabledForeground: Color = Color(.Experiment.Label.disabled)

    func makeBody(configuration: Configuration) -> some View {
        RunIconButtonContent(
            configuration: configuration,
            background: background,
            foreground: foreground,
            iconSize: iconSize,
            disabledBackground: disabledBackground,
            disabledForeground: disabledForeground
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
    let disabledBackground: Color
    let disabledForeground: Color

    private var isPressed: Bool {
        configuration.isPressed && isEnabled
    }

    var body: some View {
        configuration.label
            .frame(minWidth: iconSize, minHeight: iconSize)
            .foregroundStyle(
                isEnabled ? foreground : disabledForeground
            )
            .frame(width: buttonSize, height: buttonSize)
            .background(
                isEnabled ? background : disabledBackground,
                in: Circle()
            )
            .contentShape(Circle())
            .labcordPressFeedback(isPressed)
            .labcordMotion(.state, value: background)
    }
}
