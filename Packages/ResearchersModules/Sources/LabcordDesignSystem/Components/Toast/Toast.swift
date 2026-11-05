import SwiftUI

public enum ToastType: CaseIterable, Sendable {
    case success
    case warning
    case error
    case info

    fileprivate var foregroundColor: Color {
        switch self {
        case .success:
            Color(.Experiment.Feedback.Success.foreground)
        case .warning:
            Color(.Experiment.Feedback.Warning.foreground)
        case .error:
            Color(.Experiment.Feedback.Error.foreground)
        case .info:
            Color(.Experiment.Feedback.Info.foreground)
        }
    }

    fileprivate var icon: Icon {
        switch self {
        case .success:
            .checkCircleFill
        case .warning:
            .warning
        case .error:
            .warning
        case .info:
            .warningCircle
        }
    }

    fileprivate var subtleColor: Color {
        switch self {
        case .success:
            Color(.Experiment.Feedback.Success.subtle)
        case .warning:
            Color(.Experiment.Feedback.Warning.subtle)
        case .error:
            Color(.Experiment.Feedback.Error.subtle)
        case .info:
            Color(.Experiment.Feedback.Info.subtle)
        }
    }
}

public enum ToastAppearance: Sendable {
    case `default`
    case accent
}

public struct Toast: View {

    private let message: String
    private let type: ToastType
    private let appearance: ToastAppearance
    private let fillsWidth: Bool
    private let showLeadingIcon: Bool
    private let showDismissButton: Bool
    private let showActionButton: Bool
    private let actionTitle: String
    private let onAction: () -> Void
    private let onDismiss: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var dismissSize: CGFloat = 28

    public init(
        _ message: String,
        type: ToastType = .success,
        appearance: ToastAppearance = .default,
        fillsWidth: Bool = false,
        showLeadingIcon: Bool = true,
        actionTitle: String = "다시시도",
        onAction: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.init(
            message: message,
            type: type,
            appearance: appearance,
            fillsWidth: fillsWidth,
            showLeadingIcon: showLeadingIcon,
            showDismissButton: onDismiss != nil,
            showActionButton: onAction != nil,
            actionTitle: actionTitle,
            onAction: onAction ?? {},
            onDismiss: onDismiss ?? {}
        )
    }

    public init(
        message: String,
        type: ToastType = .success,
        appearance: ToastAppearance = .default,
        fillsWidth: Bool = false,
        showLeadingIcon: Bool = true,
        showDismissButton: Bool = true,
        showActionButton: Bool = true,
        actionTitle: String = "다시시도",
        onAction: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.message = message
        self.type = type
        self.appearance = appearance
        self.fillsWidth = fillsWidth
        self.showLeadingIcon = showLeadingIcon
        self.showDismissButton = showDismissButton
        self.showActionButton = showActionButton
        self.actionTitle = actionTitle
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    public var body: some View {
        toastContent
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .labcordMotion(.layout, value: [showLeadingIcon, showActionButton, showDismissButton])
        .padding(.horizontal, LayoutTokens.spacing16)
        .padding(.vertical, LayoutTokens.spacing16)
        .frame(minHeight: 68)
        .background {
            if appearance == .accent {
                Rectangle()
                    .fill(type.subtleColor)
                    .background(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
        }
        .background(appearance == .default ? Color(.Experiment.Fill.primary) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: LayoutTokens.radiusSm))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var toastContent: some View {
        ViewThatFits(in: .horizontal) {
            horizontalContent
                .fixedSize(horizontal: true, vertical: false)
            verticalContent
        }
    }

    private var horizontalContent: some View {
        HStack(alignment: .center, spacing: LayoutTokens.spacing12) {
            leadingContent
            if showActionButton || showDismissButton {
                actionsContent
                    .transition(.opacity)
            }
        }
    }

    private var verticalContent: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing12) {
            leadingContent
            if showActionButton || showDismissButton {
                HStack {
                    Spacer(minLength: 0)
                    actionsContent
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var leadingContent: some View {
        HStack(alignment: .center, spacing: LayoutTokens.spacing12) {
            if showLeadingIcon {
                ZStack {
                    IconArtwork(icon: type.icon, size: 28)
                        .foregroundStyle(type.foregroundColor)
                        .id(type.icon.rawValue)
                        .transition(.opacity)
                }
                .labcordMotion(.state, value: type.icon.rawValue)
                .transition(.opacity)
                .accessibilityHidden(true)
            }

            Text(message)
                .typography(Typography.body)
                .foregroundStyle(messageColor)
                .contentTransition(.opacity)
                .labcordMotion(.state, value: message)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
    }

    private var messageColor: Color {
        appearance == .accent ? type.foregroundColor : Color(.Experiment.Label.primary)
    }

    @ViewBuilder
    private var actionsContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: LayoutTokens.spacing12) {
                actionButton
                dismissButton
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .trailing, spacing: LayoutTokens.spacing12) {
                actionButton
                dismissButton
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if showActionButton {
            Button(action: onAction) {
                Text(actionTitle)
                    .foregroundStyle(
                        isEnabled
                            ? Color(.Experiment.Label.secondary)
                            : Color(.General.Action.Disabled.foreground)
                    )
                    .contentTransition(.opacity)
                    .labcordMotion(.state, value: actionTitle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.labcord(.quaternary, size: .small))
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var dismissButton: some View {
        if showDismissButton {
            Button(action: onDismiss) {
                IconArtwork(icon: .x, size: 12)
                    .foregroundStyle(
                        isEnabled
                            ? Color(.Experiment.Label.primary)
                            : Color(.General.Action.Disabled.foreground)
                    )
                    .frame(width: dismissSize, height: dismissSize)
                    .background(
                        isEnabled
                            ? Color(.Experiment.Fill.secondary)
                            : Color(.General.Action.Disabled.background),
                        in: Circle()
                    )
            }
            .buttonStyle(.labcordIcon(.quaternary, size: .small))
            .accessibilityLabel(Text("닫기"))
            .transition(.opacity)
        }
    }
}

#Preview("토스트") {
    _ = FontRegistration.register()
    return VStack {
        Toast("저장했어요.", type: .success)
        Toast("저장했어요.", type: .success, appearance: .accent)
    }
        .padding()
        .background(Color(.Experiment.Background.primary))
}
