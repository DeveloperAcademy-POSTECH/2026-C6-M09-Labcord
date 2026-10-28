import LabcordiOS
import SwiftUI

struct ExperimentHomeView: View {
    let entries: [ExperimentListEntry]
    let onAdd: () -> Void
    let onSelect: (UUID) -> Void
    let onSettings: () -> Void
    let onEdit: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let isDeleting: Bool

    var body: some View {
        List {
            section("진행 중인 실험", entries: entries.filter(\.isActive))
            section("최근 실험", entries: entries.filter { !$0.isActive })
        }
        .navigationTitle("실험")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("설정", systemImage: "gearshape", action: onSettings)
                    .accessibilityIdentifier("entry-settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("새 실험 추가", systemImage: "plus", action: onAdd)
                    .accessibilityIdentifier("entry-add")
            }
        }
    }
}

private extension ExperimentHomeView {
    func section(_ title: String, entries: [ExperimentListEntry]) -> some View {
        Section(title) {
            ForEach(entries) { entry in
                HomeExperimentRow(entry: entry) {
                    onSelect(entry.id)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("삭제", systemImage: "trash") {
                        onDelete(entry.id)
                    }
                    .tint(.red)
                    .accessibilityIdentifier("entry-delete-\(entry.id.uuidString)")
                    Button("수정", systemImage: "pencil") {
                        onEdit(entry.id)
                    }
                    .accessibilityIdentifier("entry-edit-\(entry.id.uuidString)")
                }
                .disabled(isDeleting)
            }
        }
    }
}
