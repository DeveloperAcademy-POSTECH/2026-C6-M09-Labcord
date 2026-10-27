import SwiftUI

struct HomeExperimentRow: View {
    let entry: ExperimentListEntry
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.title)
                        .font(EntryAppearance.koreanLabel(17))
                        .foregroundStyle(EntryAppearance.text)
                        .frame(height: 22)
                        .offset(x: 1 / 3, y: -0.5)
                        .lineLimit(1)

                    Text(Self.dateFormatter.string(from: entry.createdAt))
                        .font(EntryAppearance.label(15))
                        .tracking(1 / 30)
                        .foregroundStyle(EntryAppearance.secondaryText)
                        .frame(height: 20)
                        .offset(y: -1 / 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                EntryStatusBadge(title: entry.statusTitle, status: entry.status)

                Image(systemName: "chevron.forward")
                    .font(EntryAppearance.label(15))
                    .foregroundStyle(EntryAppearance.secondarySymbol)
                    .frame(width: 11)
                    .offset(y: -0.5)
            }
            .frame(minHeight: EntryAppearance.rowHeight)
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

private struct EntryStatusBadge: View {
    let title: String
    let status: ExperimentListEntry.Status

    var body: some View {
        Text(title)
            .font(EntryAppearance.label(15.75))
            .foregroundStyle(foreground)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: textWidth, height: 20)
            .offset(y: -0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: RoundedRectangle(cornerRadius: 4))
    }

    private var textWidth: CGFloat {
        switch status {
        case .inProgress: 45
        case .paused: 59
        case .preparing, .completed: 28
        }
    }

    private var foreground: Color {
        switch status {
        case .inProgress: Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)
        case .paused: EntryAppearance.accent
        case .preparing: Color(red: 1, green: 141 / 255, blue: 40 / 255)
        case .completed: Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.6)
        }
    }

    private var background: Color {
        switch status {
        case .inProgress: Color(red: 236 / 255, green: 252 / 255, blue: 240 / 255)
        case .paused: Color(red: 157 / 255, green: 196 / 255, blue: 1).opacity(0.2)
        case .preparing: Color(red: 1, green: 219 / 255, blue: 76 / 255).opacity(0.2)
        case .completed: Color(white: 120 / 255).opacity(0.2)
        }
    }
}
