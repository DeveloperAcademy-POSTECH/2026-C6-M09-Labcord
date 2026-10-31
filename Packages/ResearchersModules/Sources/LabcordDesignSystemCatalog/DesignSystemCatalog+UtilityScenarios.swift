import LabcordDesignSystem
import LabcordShared
import SwiftUI

struct CatalogControlStatusBadgeScenario: View {
    @State private var status = ExperimentStatus.preparing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabcordStatusBadge(status: status)
                .accessibilityIdentifier("catalog.scenario.statusBadge.preview")
            Picker("상태", selection: $status) {
                catalogPickerOptions(
                    [ExperimentStatus.preparing, .inProgress, .paused, .completed]
                )
            }
            .accessibilityIdentifier("catalog.scenario.statusBadge.state")
        }
    }
}

struct CatalogControlSeparatorScenario: View {
    @State private var isVertical = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 16) {
                Text(isVertical ? "수직 구분선" : "수평 구분선")
                    .typography(Typography.subheadline)
                if isVertical {
                    HStack(spacing: 12) {
                        Text("Default")
                        LabcordSeparator(orientation: .vertical)
                            .frame(height: 24)
                        Text("Vertical")
                    }
                } else {
                    LabcordSeparator()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("catalog.scenario.separator.preview")
            Picker("방향", selection: $isVertical) {
                Text("Horizontal").tag(false)
                Text("Vertical").tag(true)
            }
            .accessibilityIdentifier("catalog.scenario.separator.orientation")
        }
    }
}

struct CatalogControlLoadingScenario: View {
    @State private var size = LabcordProgressViewStyle.Size.small

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView()
                .progressViewStyle(.labcord(size: size))
                .accessibilityLabel(Text("로딩 중"))
                .accessibilityIdentifier("catalog.scenario.loading.preview")
            Picker("크기", selection: $size) {
                ForEach(LabcordProgressViewStyle.Size.allCases, id: \.rawValue) { size in
                    Text(String(describing: size).capitalized).tag(size)
                }
            }
            .accessibilityIdentifier("catalog.scenario.loading.size")
        }
    }
}
