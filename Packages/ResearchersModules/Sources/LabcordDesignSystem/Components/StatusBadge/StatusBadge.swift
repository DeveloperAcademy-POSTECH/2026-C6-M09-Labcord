import SwiftUI

public struct StatusBadge: View {
    public enum Status: Equatable, Sendable {
        case ready
        case paused
        case completed
    }

    private let status: Status
    private let label: String

    public init(status: Status, label: String? = nil) {
        self.status = status
        self.label = label ?? status.defaultLabel
    }

    public var body: some View {
        Text(label)
            .typography(Typography.subheadline)
            .foregroundStyle(status.foregroundColor)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, LayoutTokens.spacing8)
            .padding(.vertical, LayoutTokens.spacing4)
            .frame(minWidth: 70, minHeight: 28)
            .background(status.backgroundColor, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(Text(label))
    }
}

private extension StatusBadge.Status {
    var defaultLabel: String {
        switch self {
        case .ready: "준비"
        case .paused: "일시정지"
        case .completed: "완료"
        }
    }

    var foregroundColor: Color {
        switch self {
        case .ready: Color(.General.Label.tertiary)
        case .paused: Color(.General.Experiment.Status.Paused.foreground)
        case .completed: Color(.General.Experiment.Status.Completed.foreground)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .ready: Color(.General.Background.secondary)
        case .paused: Color(.General.Experiment.Status.Paused.background)
        case .completed: Color(.General.Experiment.Status.Completed.background)
        }
    }
}

#Preview("실험 상태 배지") {
    _ = FontRegistration.register()
    return VStack(spacing: 12) {
        StatusBadge(status: .ready)
        StatusBadge(status: .paused)
        StatusBadge(status: .completed)
    }
    .padding()
}
