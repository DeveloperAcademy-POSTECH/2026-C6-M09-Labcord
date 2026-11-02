import ComposableArchitecture
import LabcordiOS
import LabcordDesignSystem
import SwiftUI

struct ExperimentList: View {
    @Bindable var store: StoreOf<ExperimentListFeature>

    var body: some View {
        List {
            section("진행 중인 실험", icon: .flask, entries: store.entries.filter(\.isActive))
            section("최근 실험", icon: .folderOpen, entries: store.entries.filter { !$0.isActive })
        }
        .listRowSpacing(0)
        .listSectionSpacing(.custom(LayoutTokens.spacing32))
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .background(Color("General/Background/Primary"))
        .alert(
            "실험을 삭제할까요?",
            isPresented: deletionBinding,
            presenting: store.pendingDeletion
        ) { entry in
            Button("삭제", role: .destructive) {
                store.send(.deleteConfirmed(entry.id))
            }
            Button("취소", role: .cancel) {
                store.send(.deleteCancelled)
            }
        } message: { entry in
            Text("‘\(entry.title)’ 실험과 연결된 기록이 영구 삭제됩니다. 되돌릴 수 없어요.")
        }
        .alert("실험을 삭제하지 못했어요", isPresented: failureBinding(.deleting)) {
            retryButtons(for: .deleting)
        } message: {
            Text("실험은 삭제되지 않았어요. 다시 시도해 주세요.")
        }
        .alert("실험 목록을 불러오지 못했어요", isPresented: failureBinding(.loading)) {
            retryButtons(for: .loading)
        } message: {
            Text("기존 기록을 유지하고 있어요. 다시 시도해 주세요.")
        }
        .task { await store.send(.load).finish() }
    }
}

private extension ExperimentList {
    func section(_ title: String, icon: Icon, entries: [ExperimentListEntry]) -> some View {
        Section {
            ForEach(entries) { entry in
                ExperimentListItem(entry: entry) {
                    store.send(.experimentTapped(entry.id))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("삭제", systemImage: "trash") {
                        store.send(.deleteRequested(entry.id))
                    }
                    .tint(.red)
                    .accessibilityIdentifier("entry-delete-\(entry.id.uuidString)")
                }
                .listRowInsets(.all, 0)
                .disabled(store.isDeleting)
                .listRowSeparator(.hidden)
            }
        } header: {
            HStack(spacing: LayoutTokens.spacing8) {
                Image(labcordIcon: icon)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Color("Experiment/Brand/Primary"))

                Text(title)
                    .typography(Typography.headline)
                    .foregroundStyle(Color("General/Label/Primary"))
            }
            .listRowInsets(.horizontal, 0)
        }
        .listSectionMargins(.horizontal, 0)
    }

    var deletionBinding: Binding<Bool> {
        Binding(
            get: { store.pendingDeletion != nil },
            set: { if !$0 { store.send(.deleteCancelled) } }
        )
    }

    func retryButtons(for failure: ExperimentListFeature.Failure) -> some View {
        Group {
            Button("재시도") {
                store.send(.retryTapped(failure))
            }
            Button("취소", role: .cancel) {
                store.send(.dismissFailure)
            }
        }
    }

    func failureBinding(_ failure: ExperimentListFeature.Failure) -> Binding<Bool> {
        Binding(
            get: { store.failure == failure },
            set: { if !$0 { store.send(.dismissFailure) } }
        )
    }
}
