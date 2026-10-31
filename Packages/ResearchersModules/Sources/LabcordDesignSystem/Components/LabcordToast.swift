import SwiftUI

public enum LabcordToastTone: CaseIterable, Sendable {
    case success
    case warning
    case error
    case info

    fileprivate var foregroundToken: ColorToken {
        switch self {
        case .success:
            .feedbackSuccessForeground
        case .warning:
            .feedbackWarningForeground
        case .error:
            .feedbackErrorForeground
        case .info:
            .feedbackInfoForeground
        }
    }

    fileprivate var icon: LabcordIcon {
        switch self {
        case .success:
            .checkCircleFill
        case .warning:
            .warning
        case .error:
            .prohibitInsert
        case .info:
            .warningCircle
        }
    }
}

public struct LabcordToast: View {
    @Environment(\.labcordTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private let message: String
    private let tone: LabcordToastTone
    private let showLeadingIcon: Bool
    private let showDismissButton: Bool
    private let showActionButton: Bool
    private let actionTitle: String
    private let onAction: () -> Void
    private let onDismiss: () -> Void
    private let layout = LayoutTokens()

    public init(
        _ message: String,
        tone: LabcordToastTone = .success,
        showLeadingIcon: Bool = true,
        actionTitle: String = "다시시도",
        onAction: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.init(
            message: message,
            tone: tone,
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
        tone: LabcordToastTone = .success,
        showLeadingIcon: Bool = true,
        showDismissButton: Bool = true,
        showActionButton: Bool = true,
        actionTitle: String = "다시시도",
        onAction: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.message = message
        self.tone = tone
        self.showLeadingIcon = showLeadingIcon
        self.showDismissButton = showDismissButton
        self.showActionButton = showActionButton
        self.actionTitle = actionTitle
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    public var body: some View {
        toastContent
        .labcordMotion(.layout, value: [showLeadingIcon, showActionButton, showDismissButton])
        .padding(.horizontal, layout.spacing16)
        .padding(.vertical, layout.spacing12)
        .frame(minHeight: showActionButton ? 60 : nil)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, materialColorScheme)
        }
        .background(.labcord(.fillPrimary))
        .clipShape(RoundedRectangle(cornerRadius: layout.radiusSm))
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

    private var materialColorScheme: ColorScheme {
        theme.resolvedContext(for: colorScheme) == .experiment ? .dark : .light
    }

    private var horizontalContent: some View {
        HStack(alignment: .center, spacing: layout.spacing16) {
            leadingContent
            if showActionButton || showDismissButton {
                actionsContent
                    .transition(.opacity)
            }
        }
    }

    private var verticalContent: some View {
        VStack(alignment: .leading, spacing: layout.spacing12) {
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
        HStack(alignment: .center, spacing: layout.spacing16) {
            if showLeadingIcon {
                ZStack {
                    LabcordIconArtwork(icon: tone.icon, size: 20)
                        .foregroundStyle(.labcord(tone.foregroundToken))
                        .id(tone.icon.rawValue)
                        .transition(.opacity)
                }
                .labcordMotion(.state, value: tone.icon.rawValue)
                .transition(.opacity)
                .accessibilityHidden(true)
            }

            Text(message)
                .typography(Typography.headline)
                .foregroundStyle(.labcord(.labelPrimary))
                .contentTransition(.opacity)
                .labcordMotion(.state, value: message)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var actionsContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: layout.spacing12) {
                actionButton
                dismissButton
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .trailing, spacing: layout.spacing12) {
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
                LabcordIconArtwork(icon: .x, size: 12)
                    .foregroundStyle(.labcord(.labelSecondary))
            }
            .buttonStyle(.labcordIcon(.tertiary, size: .small))
            .accessibilityLabel(Text("닫기"))
            .transition(.opacity)
        }
    }
}
