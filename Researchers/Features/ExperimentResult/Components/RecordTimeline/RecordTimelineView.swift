import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct RecordTimelineView: View {
    let store: StoreOf<RecordTimelineFeature>

    var body: some View {
        let entries = store.entries
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let date = ExperimentResultDateFormatter.date(entry.date)
                let previousDate = index > 0
                    ? ExperimentResultDateFormatter.date(entries[index - 1].date)
                    : nil
                if date != previousDate {
                    Text(date)
                        .padding(.horizontal, LayoutTokens.spacing16)
                        .padding(.top, LayoutTokens.spacing8)
                }

                RecordTimelineEntryView(entry: entry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
