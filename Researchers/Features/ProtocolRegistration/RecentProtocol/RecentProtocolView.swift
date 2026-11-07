import ComposableArchitecture
import Foundation
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct RecentProtocolView: View {
    @Bindable var store: StoreOf<RecentProtocolFeature>
    @State private var detail: RecentProtocolEntry?

    var body: some View {
        Group {
            if store.loading {
                ProgressView("최근 프로토콜을 불러오고 있어요")
            } else if store.failed {
                ContentUnavailableView {
                    Label("프로토콜을 불러오지 못했어요", systemImage: "exclamationmark.circle")
                } actions: {
                    Button("다시 시도") { store.send(.load) }
                        .buttonStyle(.labcord(.secondary))
                }
            } else if store.entries.isEmpty {
                ContentUnavailableView("최근 사용한 프로토콜이 없어요", systemImage: "doc.text")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.entries) { entry in
                            LabcordDesignSystem.ExperimentListItem(
                                title: entry.title,
                                date: formattedDate(entry.createdAt),
                                status: .ready,
                                isSelected: Binding<Bool>(
                                    get: { store.selectedID == entry.id },
                                    set: { selected in
                                        if selected { _ = store.send(.select(entry.id)) }
                                    }
                                ),
                                showBadge: false
                            ) {
                                detail = entry
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                store.send(.useSelected)
            } label: {
                Text("다음").frame(maxWidth: .infinity)
            }
                .buttonStyle(.labcord(.primary, size: .large))
                .disabled(store.selectedID == nil || store.loading || store.failed)
                .padding(16)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            NavigationPageTitle("최근 사용한 프로토콜") {
                store.send(.backTapped)
            }
        }
        .navigationDestination(item: $detail) { entry in
            RecentProtocolDetailView(entry: entry) {
                store.send(.select(entry.id))
                detail = nil
            }
        }
        .task { store.send(.load) }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

#Preview("최근 사용한 프로토콜 · 빈 목록") {
    _ = FontRegistration.register()
    NavigationStack {
        RecentProtocolView(
            store: Store(initialState: RecentProtocolFeature.State()) {
                RecentProtocolFeature()
            } withDependencies: {
                $0.experimentClient.loadRecentProtocols = { [] }
            }
        )
    }
}
