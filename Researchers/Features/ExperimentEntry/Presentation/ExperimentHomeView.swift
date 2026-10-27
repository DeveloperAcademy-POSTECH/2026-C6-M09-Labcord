import SwiftUI

struct ExperimentHomeView: View {
    let entries: [ExperimentListEntry]
    let onAdd: () -> Void
    let onSelect: (UUID) -> Void
    let onSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EntryAppearance.sectionGap) {
                section("진행 중인 실험", entries: entries.filter(\.isActive), rowGap: 11)
                section("최근 실험", entries: entries.filter { !$0.isActive }, rowGap: 16)
            }
            .padding(.horizontal, EntryAppearance.homeInset)
            .padding(.top, 114)
            .padding(.bottom, 175)
        }
        .background(EntryAppearance.background)
        .overlay(alignment: .topTrailing) {
            EntryRoundButton(symbol: "gear", title: "설정", symbolSize: 22, action: onSettings)
                .accessibilityIdentifier("entry-settings")
                .padding(.trailing, 20)
                .padding(.top, 26)
        }
        .overlay(alignment: .bottomTrailing) {
            EntryRoundButton(
                symbol: "plus", title: "새 실험 추가", isProminent: true, action: onAdd
            )
            .accessibilityIdentifier("entry-add")
            .padding(.trailing, 20)
            .padding(.bottom, 83)
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
    }

    private func section(
        _ title: String, entries: [ExperimentListEntry], rowGap: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: rowGap) {
            EntryText(title, style: .headline)
                .foregroundStyle(EntryAppearance.text)

            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    HomeExperimentRow(entry: entry) { onSelect(entry.id) }
                    if !entry.isActive || entry.id != entries.last?.id {
                        EntryAppearance.separator.frame(height: 1)
                            .offset(y: entry.isActive ? -3 : 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
