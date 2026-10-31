import SwiftUI

public enum ToastType: CaseIterable, Sendable {
    case success
    case warning
    case error
    case info

    fileprivate var foregroundColor: Color {
        switch self {
        case .success:
            Color("Experiment/Feedback/Success/Foreground", bundle: .module)
        case .warning:
            Color("Experiment/Feedback/Warning/Foreground", bundle: .module)
        case .error:
            Color("Experiment/Feedback/Error/Foreground", bundle: .module)
        case .info:
            Color("Experiment/Feedback/Info/Foreground", bundle: .module)
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

public struct Toast: View {

    private let message: String
    private let type: ToastType
    private let showLeadingIcon: Bool
    private let showDismissButton: Bool
    private let showActionButton: Bool
    private let actionTitle: String
    private let onAction: () -> Void
    private let onDismiss: () -> Void
    private let layout = LayoutTokens()

    public init(
        _ message: String,
        type: ToastType = .success,
        showLeadingIcon: Bool = true,
        actionTitle: String = "다시시도",
        onAction: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.init(
            message: message,
            type: type,
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
        showLeadingIcon: Bool = true,
        showDismissButton: Bool = true,
        showActionButton: Bool = true,
        actionTitle: String = "다시시도",
        onAction: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.message = message
        self.type = type
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
                .environment(\.colorScheme, .dark)
        }
        .background(Color("Experiment/Fill/Primary", bundle: .module))
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
                    LabcordIconArtwork(icon: type.icon, size: 20)
                        .foregroundStyle(type.foregroundColor)
                        .id(type.icon.rawValue)
                        .transition(.opacity)
                }
                .labcordMotion(.state, value: type.icon.rawValue)
                .transition(.opacity)
                .accessibilityHidden(true)
            }

            Text(message)
                .typography(Typography.headline)
                .foregroundStyle(Color("Experiment/Label/Primary", bundle: .module))
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
                    .foregroundStyle(Color("Experiment/Label/Secondary", bundle: .module))
            }
            .buttonStyle(.labcordIcon(.tertiary, size: .small))
            .accessibilityLabel(Text("닫기"))
            .transition(.opacity)
        }
    }
}

#Preview("토스트") {
    _ = FontRegistration.register()
    return Toast("저장했어요.", type: .success)
        .padding()
        .background(Color("Experiment/Background/Primary", bundle: .module))
}
