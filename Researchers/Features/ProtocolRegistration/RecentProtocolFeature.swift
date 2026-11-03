import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

@Reducer
struct RecentProtocolFeature {
    @ObservableState
    struct State: Equatable {
        var entries: [RecentProtocolEntry] = []
        var selectedID: UUID?
        var loading = false
        var failed = false
    }

    enum Action: Equatable {
        case load
        case loaded([RecentProtocolEntry])
        case loadFailed
        case select(UUID)
        case useSelected
        case backTapped
    }

    @Dependency(\.experimentClient) var experimentClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .load:
                guard !state.loading else { return .none }
                state.loading = true
                state.failed = false
                return .run { send in
                    do {
                        await send(.loaded(try await experimentClient.loadRecentProtocols()))
                    } catch {
                        await send(.loadFailed)
                    }
                }
            case let .loaded(entries):
                state.loading = false
                state.entries = entries
                if !entries.contains(where: { $0.id == state.selectedID }) {
                    state.selectedID = nil
                }
                return .none
            case .loadFailed:
                state.loading = false
                state.failed = true
                return .none
            case let .select(id):
                guard state.entries.contains(where: { $0.id == id }) else { return .none }
                state.selectedID = id
                return .none
            case .useSelected, .backTapped:
                return .none
            }
        }
    }
}

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
        .navigationTitle("최근 사용한 프로토콜")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("뒤로 가기", systemImage: "chevron.backward") {
                    store.send(.backTapped)
                }
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

private struct RecentProtocolDetailView: View {
    let entry: RecentProtocolEntry
    let select: () -> Void
    @State private var expandedGroups: Set<String> = []

    private var groups: [(String, [String])] {
        [
            ("시약·재료", entry.materials), ("샘플·분석 대상", entry.samples),
            ("실험 용어", entry.glossaryTerms), ("단위", entry.units)
        ]
    }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text(entry.title).typography(Typography.title3)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Text("타이머").typography(Typography.calloutSemiBold)
                            Text("\(entry.timerSeconds.count)")
                                .typography(Typography.subheadline)
                                .foregroundStyle(Color(
                                    "General/Label/Tertiary",
                                    bundle: LabcordDesignSystemResources.bundle
                                ))
                        }
                        if entry.timerSeconds.isEmpty {
                            Text("타이머가 없어요")
                        } else {
                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(), spacing: 12), count: 3
                                ),
                                spacing: 12
                            ) {
                                ForEach(
                                    Array(entry.timerSeconds.enumerated()), id: \.offset
                                ) { item in
                                    Text(Duration.seconds(item.element), format: .labcordDuration)
                                        .typography(Typography.body)
                                        .padding(.horizontal, 8)
                                        .frame(
                                            maxWidth: .infinity, minHeight: 56, alignment: .leading
                                        )
                                        .background(
                                            Color(
                                                "General/Fill/Primary",
                                                bundle: LabcordDesignSystemResources.bundle
                                            ),
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("추출한 용어").typography(Typography.calloutSemiBold)
                        Text("프로토콜에서 추출한 전문 용어를 음성 인식에 반영해요.")
                            .typography(Typography.subheadline)
                            .foregroundStyle(Color(
                                "General/Label/Secondary",
                                bundle: LabcordDesignSystemResources.bundle
                            ))
                        ForEach(groups, id: \.0) { title, terms in
                            Accordion(title, count: terms.count, isExpanded: Binding(
                                get: { expandedGroups.contains(title) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedGroups.insert(title)
                                    } else {
                                        expandedGroups.remove(title)
                                    }
                                }
                            )) {
                                if terms.isEmpty {
                                    Text("용어가 없어요").typography(Typography.subheadline)
                                } else {
                                    RecentTermFlow(spacing: 12) {
                                        ForEach(Array(terms.enumerated()), id: \.offset) { term in
                                            Text(term.element)
                                                .typography(Typography.subheadline)
                                                .foregroundStyle(Color(
                                                    "General/Label/Brand",
                                                    bundle: LabcordDesignSystemResources.bundle
                                                ))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 7)
                                                .background(Color(
                                                    "General/Fill/Selected",
                                                    bundle: LabcordDesignSystemResources.bundle
                                                ), in: Capsule())
                                                .overlay {
                                                    Capsule().strokeBorder(Color(
                                                        "General/Border/Focused",
                                                        bundle: LabcordDesignSystemResources.bundle
                                                    ))
                                                }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: select) {
                    Text("프로토콜 선택").frame(maxWidth: .infinity)
                }
                    .buttonStyle(.labcord(.primary, size: .large))
                    .padding(16)
            }
            .navigationTitle("프로토콜 상세")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RecentTermFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(0) {
            $0 + $1.sizeThatFits(.unspecified).width
        }
        let rows = rows(for: width, subviews: subviews)
        return CGSize(width: width, height: rows.reduce(0) { $0 + $1.height }
                      + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var originY = bounds.minY
        for row in rows(for: bounds.width, subviews: subviews) {
            var originX = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(
                    ProposedViewSize(width: bounds.width, height: nil)
                )
                subviews[index].place(
                    at: CGPoint(x: originX, y: originY), proposal: ProposedViewSize(size)
                )
                originX += size.width + spacing
            }
            originY += row.height + spacing
        }
    }

    private func rows(
        for width: CGFloat, subviews: Subviews
    ) -> [(indices: [Int], height: CGFloat)] {
        var result: [(indices: [Int], height: CGFloat)] = []
        var indices: [Int] = []
        var occupied: CGFloat = 0
        var height: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            if !indices.isEmpty && occupied + spacing + size.width > width {
                result.append((indices, height))
                indices = []
                occupied = 0
                height = 0
            }
            occupied += (indices.isEmpty ? 0 : spacing) + size.width
            indices.append(index)
            height = max(height, size.height)
        }
        if !indices.isEmpty { result.append((indices, height)) }
        return result
    }
}
