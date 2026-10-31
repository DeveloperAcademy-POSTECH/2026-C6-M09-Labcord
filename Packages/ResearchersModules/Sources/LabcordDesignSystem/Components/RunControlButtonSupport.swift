import SwiftUI

@MainActor
struct RunIconButtonStyle: ButtonStyle {
    let background: ColorToken
    let foreground: ColorToken
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
    let background: ColorToken
    let foreground: ColorToken
    let iconSize: CGFloat

    private var isPressed: Bool {
        configuration.isPressed && isEnabled
    }

    var body: some View {
        configuration.label
            .frame(minWidth: iconSize, minHeight: iconSize)
            .foregroundStyle(.labcord(isEnabled ? foreground : .labelDisabled))
            .frame(width: buttonSize, height: buttonSize)
            .background(
                .labcord(isEnabled ? background : .fillDisabled),
                in: Circle()
            )
            .contentShape(Circle())
            .labcordPressFeedback(isPressed)
            .labcordMotion(.state, value: background)
    }
}
