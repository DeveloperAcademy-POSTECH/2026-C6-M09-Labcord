import LabcordShared
import SwiftUI

public struct StatusBadge: View {

    private let status: ExperimentStatus
    private let label: String

    public init(status: ExperimentStatus, label: String? = nil) {
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

private extension ExperimentStatus {
    var defaultLabel: String {
        switch self {
        case .preparing: "준비"
        case .inProgress: "진행 중"
        case .paused: "일시정지"
        case .completed: "완료"
        }
    }

    var foregroundColor: Color {
        switch self {
        case .preparing: Color(.General.Label.tertiary)
        case .inProgress: Color(.General.Experiment.Status.InProgress.foreground)
        case .paused: Color(.General.Experiment.Status.Paused.foreground)
        case .completed: Color(.General.Experiment.Status.Completed.foreground)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .preparing: Color(.General.Background.secondary)
        case .inProgress: Color(.General.Experiment.Status.InProgress.background)
        case .paused: Color(.General.Experiment.Status.Paused.background)
        case .completed: Color(.General.Experiment.Status.Completed.background)
        }
    }
}

#Preview("실험 상태 배지") {
    _ = FontRegistration.register()
    return VStack(spacing: 12) {
        StatusBadge(status: .preparing)
        StatusBadge(status: .inProgress)
        StatusBadge(status: .paused)
        StatusBadge(status: .completed)
    }
    .padding()
}
