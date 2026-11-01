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

                HStack(spacing: 4) {
                    Text(entry.statusTitle)
                    if entry.hasRunningTimer {
                        Image(systemName: "timer")
                            .accessibilityLabel("실행 중인 타이머 있음")
                    }
                }
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
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()
}

extension ExperimentListEntry {
    var statusTitle: String {
        switch status {
        case .ready: "준비"
        case .paused: "일시 정지"
        case .completed: "완료"
        }
    }

}
