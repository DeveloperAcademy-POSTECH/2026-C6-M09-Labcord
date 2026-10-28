import LabcordiOS
import SwiftUI

struct HomeExperimentRow: View {
    let entry: ExperimentListEntry
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.title)
                        .font(.body)
                        .foregroundStyle(EntryAppearance.text)
                        .lineLimit(1)

                    Text(Self.dateFormatter.string(from: entry.createdAt))
                        .font(.subheadline)
                        .foregroundStyle(EntryAppearance.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.statusTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)

                Image("EntryChevronSampled")
                    .renderingMode(.template)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 11, height: 20)
                    .foregroundStyle(EntryAppearance.secondarySymbol)
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
