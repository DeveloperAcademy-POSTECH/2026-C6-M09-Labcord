import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct ExperimentListItem: View {
    let entry: ExperimentListEntry
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: LayoutTokens.spacing4) {
                    Text(entry.title)
                        .typography(Typography.body)
                        .foregroundStyle(Color("General/Label/Primary"))
                        .lineLimit(1)

                    Text(Self.dateFormatter.string(from: entry.createdAt))
                        .typography(Typography.subheadline)
                        .foregroundStyle(Color("General/Label/Tertiary"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: LayoutTokens.spacing12) {
                    if entry.hasRunningTimer || entry.status != .ready {
                        if entry.status == .paused {
                            StatusBadge(status: .paused, label: "일시 정지")
                        } else if entry.status == .completed {
                            StatusBadge(status: .completed)
                        }
                    }

                    Image(labcordIcon: .caretRight)
                        .resizable()
                        .foregroundStyle(Color("General/Label/Tertiary"))
                        .frame(width: 16, height: 16)
                        .padding(LayoutTokens.spacing8)
                }
            }
            .padding(LayoutTokens.spacing8)
            .contentShape(Rectangle())
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color("General/Border/Default"))
                .frame(height: 0.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
