import ComposableArchitecture
import SwiftUI

struct ExperimentEntryView: View {
    @Bindable var store: StoreOf<ExperimentEntryFeature>

    var body: some View {
        NavigationStack {
            ExperimentHomeView(
                entries: store.entries,
                onAdd: { store.send(.addTapped) },
                onSelect: { store.send(.experimentTapped($0)) },
                onSettings: { store.send(.settingsTapped) },
                onEdit: { store.send(.editTapped($0)) },
                onDelete: { store.send(.deleteRequested($0)) },
                isDeleting: store.isDeleting
            )
            .alert("실험을 삭제할까요?", isPresented: deletionBinding,
                   presenting: store.pendingDeletion) { entry in
                Button("삭제", role: .destructive) { store.send(.deleteConfirmed(entry.id)) }
                Button("취소", role: .cancel) { store.send(.deleteCancelled) }
            } message: { entry in
                Text("‘\(entry.title)’ 실험과 연결된 기록이 영구 삭제됩니다. 되돌릴 수 없어요.")
            }
            .alert("실험을 삭제하지 못했어요", isPresented: failureBinding(.deleting)) {
                retryButtons(for: .deleting)
            } message: {
                Text("실험은 삭제되지 않았어요. 다시 시도해 주세요.")
            }
            .navigationDestination(
                isPresented: $store.isRegistering.sending(\.registrationPresented)
            ) {
                ProtocolRegistrationView(
                    isSaving: store.isSaving,
                    onBack: { store.send(.registrationPresented(false)) },
                    onSkip: { store.send(.skipTapped) },
                    onSource: { store.send(.sourceTapped($0)) }
                )
                .alert("실험을 저장하지 못했어요", isPresented: failureBinding(.saving)) {
                    retryButtons(for: .saving)
                } message: {
                    Text("실험은 등록되지 않았어요. 다시 시도해 주세요.")
                }
            }
            .alert("실험 목록을 불러오지 못했어요", isPresented: failureBinding(.loading)) {
                retryButtons(for: .loading)
            } message: {
                Text("기존 기록을 유지하고 있어요. 다시 시도해 주세요.")
            }
        }
        .tint(EntryAppearance.text)
        .preferredColorScheme(.light)
        .statusBarHidden()
        .task { await store.send(.load).finish() }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { store.pendingDeletion != nil },
            set: { if !$0 { store.send(.deleteCancelled) } }
        )
    }

    private func retryButtons(for failure: ExperimentEntryFeature.Failure) -> some View {
        Group {
            Button("재시도") { store.send(.retryTapped(failure)) }
            Button("취소", role: .cancel) { store.send(.dismissFailure) }
        }
    }

    private func failureBinding(_ failure: ExperimentEntryFeature.Failure) -> Binding<Bool> {
        Binding(
            get: { store.failure == failure },
            set: { if !$0 { store.send(.dismissFailure) } }
        )
    }
}
