import SwiftUI

struct HomeExperimentRow: View {
    let entry: ExperimentListEntry
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.title)
                        .font(EntryAppearance.label(17))
                        .tracking(-0.43)
                        .foregroundStyle(EntryAppearance.text)
                        .frame(height: 22)
                        .lineLimit(1)

                    Text(Self.dateFormatter.string(from: entry.createdAt))
                        .font(EntryAppearance.label(15))
                        .tracking(-0.23)
                        .foregroundStyle(EntryAppearance.secondaryText)
                        .frame(height: 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                EntryStatusBadge(title: entry.statusTitle)

                Image(systemName: "chevron.forward")
                    .font(EntryAppearance.label(15))
                    .foregroundStyle(EntryAppearance.secondaryText)
                    .frame(width: 11)
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

    var body: some View {
        Text(title)
            .font(EntryAppearance.label(15))
            .tracking(-0.23)
            .foregroundStyle(foreground)
            .frame(height: 20)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: RoundedRectangle(cornerRadius: 4))
    }

    private var foreground: Color {
        switch title {
        case "진행 중": Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)
        case "일시 정지": EntryAppearance.accent
        case "준비": Color(red: 1, green: 141 / 255, blue: 40 / 255)
        default: Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.6)
        }
    }

    private var background: Color {
        switch title {
        case "진행 중": Color(red: 236 / 255, green: 252 / 255, blue: 240 / 255)
        case "일시 정지": Color(red: 157 / 255, green: 196 / 255, blue: 1).opacity(0.2)
        case "준비": Color(red: 1, green: 219 / 255, blue: 76 / 255).opacity(0.2)
        default: Color(white: 120 / 255).opacity(0.2)
        }
    }
}
