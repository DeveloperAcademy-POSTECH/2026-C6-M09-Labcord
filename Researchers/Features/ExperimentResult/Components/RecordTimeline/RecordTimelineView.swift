import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct RecordTimelineView: View {
    let store: StoreOf<RecordTimelineFeature>

    var body: some View {
        let entries = store.entries

        LazyVStack(alignment: .leading, spacing: LayoutTokens.spacing8) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let date = ExperimentResultDateFormatter.date(entry.date)
                let previousDate = index > 0
                    ? ExperimentResultDateFormatter.date(entries[index - 1].date)
                    : nil

                if date != previousDate {
                    Text(date)
                        .typography(Typography.headline)
                        .foregroundStyle(Color("General/Label/Secondary"))
                        .padding(.horizontal, LayoutTokens.spacing16)
                        .padding(.vertical, LayoutTokens.spacing4)
                }

                RecordTimelineEntryView(entry: entry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
