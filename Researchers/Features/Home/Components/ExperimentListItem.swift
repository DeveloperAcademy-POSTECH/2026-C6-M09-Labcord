import LabcordiOS
import SwiftUI

struct ExperimentListItem: View {
    let entry: ExperimentListEntry
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.title)
                        .font(.body)
                        .lineLimit(1)

                    Text(Self.dateFormatter.string(from: entry.createdAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.statusTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("experiment-row-\(entry.id.uuidString)")
        .accessibilityElement(children: .combine)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()
}

extension ExperimentListEntry {
    var statusTitle: String {
        switch status {
        case .preparing: "준비"
        case .inProgress: "진행 중"
        case .paused: "일시 정지"
        case .completed: "종료"
        }
    }

}
