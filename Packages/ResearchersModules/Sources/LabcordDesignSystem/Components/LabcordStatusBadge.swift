import SwiftUI

public struct LabcordStatusBadge: View {
    public enum Status: String, CaseIterable, Sendable {
        case ready
        case running
        case paused
        case completed

        var defaultLabel: String {
            switch self {
            case .ready:
                "준비"
            case .running:
                "진행 중"
            case .paused:
                "일시정지"
            case .completed:
                "완료"
            }
        }

        var foregroundToken: ColorToken {
            switch self {
            case .ready:
                .experimentStatusReadyForeground
            case .running:
                .experimentStatusInProgressForeground
            case .paused:
                .experimentStatusPausedForeground
            case .completed:
                .experimentStatusCompletedForeground
            }
        }

        var backgroundToken: ColorToken {
            switch self {
            case .ready:
                .experimentStatusReadyBackground
            case .running:
                .experimentStatusInProgressBackground
            case .paused:
                .experimentStatusPausedBackground
            case .completed:
                .experimentStatusCompletedBackground
            }
        }
    }

    private let status: Status
    private let label: String
    private let layout = LayoutTokens()

    @Environment(\.labcordTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    public init(status: Status, label: String? = nil) {
        self.status = status
        self.label = label ?? status.defaultLabel
    }

    private var usesGeneralReadyColors: Bool {
        status == .ready && theme.resolvedContext(for: colorScheme) == .general
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
