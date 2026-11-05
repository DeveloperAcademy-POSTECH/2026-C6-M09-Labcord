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

                    HStack(spacing: LayoutTokens.spacing10) {
                        Text(Self.dateFormatter.string(from: entry.createdAt))
                            .typography(Typography.subheadline)
                            .foregroundStyle(Color("General/Label/Tertiary"))

                        if let endsAt = entry.lastRunningTimerEndsAt {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                if context.date < endsAt {
                                    HStack(spacing: LayoutTokens.spacing4) {
                                        Image(labcordIcon: .dot)
                                            .resizable()
                                            .frame(width: 16, height: 16)

                                        Text("타이머 진행 중")
                                            .typography(Typography.subheadline)
                                    }
                                    .foregroundStyle(Color("General/Timer/Identity/04"))
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(labcordIcon: .caretRight)
                    .resizable()
                    .foregroundStyle(Color("General/Label/Tertiary"))
                    .frame(width: 16, height: 16)
                    .padding(LayoutTokens.spacing8)
            }
            .padding(LayoutTokens.spacing8)
            .contentShape(Rectangle())
        }
        .background(Color("General/Background/Primary"))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color("General/Border/Default"))
                .frame(height: 0.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
