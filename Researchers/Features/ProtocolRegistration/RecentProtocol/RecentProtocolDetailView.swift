import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct RecentProtocolDetailView: View {
    @State private var store: StoreOf<RecentProtocolDetailFeature>
    let select: () -> Void

    init(store: StoreOf<RecentProtocolDetailFeature>, select: @escaping () -> Void) {
        _store = State(initialValue: store)
        self.select = select
    }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text(store.title).typography(Typography.title2Bold)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Text("타이머").typography(Typography.calloutSemiBold)
                            Text("\(store.timerSeconds.count)")
                                .typography(Typography.subheadline)
                                .foregroundStyle(Color(
                                    "General/Label/Tertiary"
                                ))
                        }
                        if store.timerSeconds.isEmpty {
                            Text("타이머가 없어요")
                        } else {
                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(), spacing: 12), count: 3
                                ),
                                spacing: 12
                            ) {
                                ForEach(
                                    Array(store.timerSeconds.enumerated()), id: \.offset
                                ) { item in
                                    ProtocolTimerRow(
                                        duration: .seconds(item.element),
                                        rows: item.element >= 3_600 ? .two : .one,
                                        showEditButton: false
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
                                "General/Label/Secondary"
                            ))
                        ForEach(store.groups, id: \.title) { group in
                            Accordion(group.title, count: group.terms.count, isExpanded: Binding(
                                get: { store.expandedGroups.contains(group.title) },
                                set: { store.send(.expandedChanged(group.title, $0)) }
                            )) {
                                if group.terms.isEmpty {
                                    Text("용어가 없어요").typography(Typography.subheadline)
                                } else {
                                    RecentTermFlow(spacing: 12) {
                                        ForEach(
                                            Array(group.terms.enumerated()), id: \.offset
                                        ) { term in
                                            Text(term.element)
                                                .typography(Typography.subheadline)
                                                .foregroundStyle(Color(
                                                    "General/Label/Brand"
                                                ))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 7)
                                                .background(Color(
                                                    "General/Fill/Selected"
                                                ), in: Capsule())
                                                .overlay {
                                                    Capsule().strokeBorder(Color(
                                                        "General/Border/Focused"
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
            .toolbar(.visible, for: .navigationBar)
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

#Preview("최근 프로토콜 상세") {
    let fontRegistration = FontRegistration.register()
    NavigationStack {
        RecentProtocolDetailView(
            store: Store(initialState: RecentProtocolDetailFeature.State(
                title: "촉매 반응 조건 비교 실험",
                timerSeconds: [600, 30, 60, 86_399],
                groups: [
                    .init(title: "시약·재료", terms: ["시약", "완충액"]),
                    .init(title: "샘플·분석 대상", terms: ["샘플"]),
                    .init(title: "실험 용어", terms: ["촉매"]),
                    .init(title: "단위", terms: ["mL"])
                ]
            )) {
                RecentProtocolDetailFeature()
            }
        ) {}
    }
    .id(fontRegistration)
}
