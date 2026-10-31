import LabcordShared
import SwiftUI

public struct LabcordStatusBadge: View {

    private let status: ExperimentStatus
    private let label: String
    private let layout = LayoutTokens()

    @Environment(\.labcordTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    public init(status: ExperimentStatus, label: String? = nil) {
        self.status = status
        self.label = label ?? status.defaultLabel
    }

    private var usesGeneralReadyColors: Bool {
        status == .preparing && theme.resolvedContext(for: colorScheme) == .general
    }

    private var foregroundToken: ColorToken {
        usesGeneralReadyColors ? .labelTertiary : status.foregroundToken
    }

    private var backgroundToken: ColorToken {
        usesGeneralReadyColors ? .backgroundSecondary : status.backgroundToken
    }

    public var body: some View {
        Text(label)
            .typography(Typography.subheadline)
            .foregroundStyle(.labcord(foregroundToken))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, layout.spacing8)
            .padding(.vertical, layout.spacing4)
            .frame(minWidth: 70, minHeight: 28)
            .background(.labcord(backgroundToken), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(Text(label))
    }
}

private extension ExperimentStatus {
    var defaultLabel: String {
        switch self {
        case .preparing: "준비"
        case .inProgress: "진행 중"
        case .paused: "일시정지"
        case .completed: "완료"
        }
    }

    var foregroundToken: ColorToken {
        switch self {
        case .preparing: .experimentStatusReadyForeground
        case .inProgress: .experimentStatusInProgressForeground
        case .paused: .experimentStatusPausedForeground
        case .completed: .experimentStatusCompletedForeground
        }
    }

    var backgroundToken: ColorToken {
        switch self {
        case .preparing: .experimentStatusReadyBackground
        case .inProgress: .experimentStatusInProgressBackground
        case .paused: .experimentStatusPausedBackground
        case .completed: .experimentStatusCompletedBackground
        }
    }
}
